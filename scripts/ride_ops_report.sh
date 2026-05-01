#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/ops/pi/docker-compose.postgres.yml}"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/ops/pi/.env}"

MATCHING_STALE_SECS="${RIDE_REPORT_MATCHING_STALE_SECS:-180}"
MATCHING_NO_OFFER_STALE_SECS="${RIDE_REPORT_MATCHING_NO_OFFER_STALE_SECS:-45}"
PENDING_OFFER_STALE_SECS="${RIDE_REPORT_PENDING_OFFER_STALE_SECS:-90}"
DRIVER_PRESENCE_STALE_SECS="${RIDE_REPORT_DRIVER_PRESENCE_STALE_SECS:-45}"
LIVE_STATE_STALE_SECS="${RIDE_REPORT_LIVE_STATE_STALE_SECS:-45}"
RESERVED_FEE_HOLD_STALE_SECS="${RIDE_REPORT_RESERVED_FEE_HOLD_STALE_SECS:-900}"
DETAIL_LIMIT="${RIDE_REPORT_DETAIL_LIMIT:-5}"
FAIL_ON_FINDINGS="${RIDE_REPORT_FAIL_ON_FINDINGS:-0}"
RIDE_OPERATOR_ALLOWED_ROLES=(
  "driver_ops"
  "city_manager"
  "support_l1"
  "support_l2"
  "finance"
  "compliance_risk"
  "marketing"
  "bi_audit_read_only"
  "admin"
  "superadmin"
  "ops"
)

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ride-report: missing required command: ${cmd}" >&2
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

compose_container_id() {
  local service="$1"
  compose ps -q "$service" | head -n1
}

inspect_container_health_and_restarts() {
  local container_id="$1"
  if [[ -z "$container_id" ]]; then
    printf 'missing|0'
    return
  fi
  docker inspect \
    --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}|{{.RestartCount}}' \
    "$container_id"
}

is_true_like() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$value" == "1" || "$value" == "true" || "$value" == "on" || "$value" == "yes" ]]
}

service_is_healthy_like() {
  local status
  status="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$status" == "healthy" || "$status" == "running" ]]
}

require_integer() {
  local name="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "ride-report: ${name} must be a non-negative integer (got ${value})." >&2
    exit 1
  fi
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
    psql -v ON_ERROR_STOP=1 -U "$pg_user" -d "$db_name" -AtF '|' -c "$sql" </dev/null
}

emit_detail_section() {
  local label="$1"
  local rows="$2"
  printf '\n[%s]\n' "$label"
  if [[ -z "$rows" ]]; then
    printf 'none\n'
    return
  fi
  printf '%s\n' "$rows"
}

sql_quoted_csv() {
  local first=1
  local value
  for value in "$@"; do
    if (( first )); then
      first=0
    else
      printf ','
    fi
    printf "'%s'" "$value"
  done
}

require_cmd docker
require_cmd awk

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ride-report: env file not found: ${ENV_FILE}" >&2
  exit 1
fi

for pair in \
  "RIDE_REPORT_MATCHING_STALE_SECS:${MATCHING_STALE_SECS}" \
  "RIDE_REPORT_MATCHING_NO_OFFER_STALE_SECS:${MATCHING_NO_OFFER_STALE_SECS}" \
  "RIDE_REPORT_PENDING_OFFER_STALE_SECS:${PENDING_OFFER_STALE_SECS}" \
  "RIDE_REPORT_DRIVER_PRESENCE_STALE_SECS:${DRIVER_PRESENCE_STALE_SECS}" \
  "RIDE_REPORT_LIVE_STATE_STALE_SECS:${LIVE_STATE_STALE_SECS}" \
  "RIDE_REPORT_RESERVED_FEE_HOLD_STALE_SECS:${RESERVED_FEE_HOLD_STALE_SECS}" \
  "RIDE_REPORT_DETAIL_LIMIT:${DETAIL_LIMIT}"; do
  require_integer "${pair%%:*}" "${pair#*:}"
done

PG_USER="$(read_env POSTGRES_USER)"
PG_PASSWORD="$(read_env POSTGRES_PASSWORD)"
AUTH_DB_URL="$(read_env DB_URL)"
PAYMENTS_DB_URL="$(read_env PAYMENTS_DB_URL)"
CHAT_DB_URL="$(read_env CHAT_DB_URL)"
FCM_SERVER_KEY="$(read_env FCM_SERVER_KEY)"

if [[ -z "$PG_USER" || -z "$PG_PASSWORD" || -z "$AUTH_DB_URL" ]]; then
  echo "ride-report: expected POSTGRES_USER, POSTGRES_PASSWORD, and DB_URL in ${ENV_FILE}" >&2
  exit 1
fi
if [[ -z "$PAYMENTS_DB_URL" ]]; then
  PAYMENTS_DB_URL="$AUTH_DB_URL"
fi
if [[ -z "$CHAT_DB_URL" ]]; then
  CHAT_DB_URL="$AUTH_DB_URL"
fi

AUTH_DB_NAME="$(db_name_from_url "$AUTH_DB_URL")"
PAYMENTS_DB_NAME="$(db_name_from_url "$PAYMENTS_DB_URL")"
CHAT_DB_NAME="$(db_name_from_url "$CHAT_DB_URL")"

bff_container_id="$(compose_container_id bff || true)"
payments_container_id="$(compose_container_id payments || true)"
chat_container_id="$(compose_container_id chat || true)"

bff_health_and_restarts="$(inspect_container_health_and_restarts "$bff_container_id")"
payments_health_and_restarts="$(inspect_container_health_and_restarts "$payments_container_id")"
chat_health_and_restarts="$(inspect_container_health_and_restarts "$chat_container_id")"

bff_service_status="${bff_health_and_restarts%%|*}"
bff_restart_count="${bff_health_and_restarts#*|}"
payments_service_status="${payments_health_and_restarts%%|*}"
payments_restart_count="${payments_health_and_restarts#*|}"
chat_service_status="${chat_health_and_restarts%%|*}"
chat_restart_count="${chat_health_and_restarts#*|}"

bff_service_unhealthy=0
payments_service_unhealthy=0
chat_service_unhealthy=0
if ! service_is_healthy_like "$bff_service_status"; then
  bff_service_unhealthy=1
fi
if ! service_is_healthy_like "$payments_service_status"; then
  payments_service_unhealthy=1
fi
if ! service_is_healthy_like "$chat_service_status"; then
  chat_service_unhealthy=1
fi

fcm_server_key_missing=0
if [[ -z "$FCM_SERVER_KEY" ]]; then
  fcm_server_key_missing=1
fi

auth_summary_sql="$(cat <<SQL
select 'matching_stale', count(*)::bigint
from auth_ride_trips
where status = 'matching'
  and status_updated_at < now() - make_interval(secs => ${MATCHING_STALE_SECS})
union all
select 'matching_without_pending_offer_stale', count(*)::bigint
from auth_ride_trips trip
where trip.status = 'matching'
  and trip.status_updated_at < now() - make_interval(secs => ${MATCHING_NO_OFFER_STALE_SECS})
  and not exists (
    select 1
    from auth_ride_dispatch_offers offers
    where offers.ride_id = trip.ride_id
      and offers.status = 'pending'
  )
union all
select 'pending_offers_stale', count(*)::bigint
from auth_ride_dispatch_offers
where status = 'pending'
  and offered_at < now() - make_interval(secs => ${PENDING_OFFER_STALE_SECS})
union all
select 'online_presence_stale', count(*)::bigint
from auth_ride_driver_presence
where availability_status = 'online'
  and last_seen_at < now() - make_interval(secs => ${DRIVER_PRESENCE_STALE_SECS})
union all
select 'active_trips_without_fresh_live_state', count(*)::bigint
from auth_ride_trips trip
left join auth_ride_trip_live_state live
  on live.ride_id = trip.ride_id
where trip.status in ('driver_assigned', 'driver_arriving', 'driver_arrived', 'trip_started', 'trip_in_progress')
  and (
    live.ride_id is null
    or coalesce(live.last_location_at, live.updated_at)
      < now() - make_interval(secs => ${LIVE_STATE_STALE_SECS})
  )
union all
select 'active_trips_missing_driver', count(*)::bigint
from auth_ride_trips
where status in ('driver_assigned', 'driver_arriving', 'driver_arrived', 'trip_started', 'trip_in_progress')
  and coalesce(driver_account_id, '') = '';
SQL
)"

payments_holds_schema_sql="$(cat <<'SQL'
select coalesce(
  (
    select schemaname
    from pg_tables
    where tablename = 'driver_ride_fee_holds'
    order by
      case when schemaname = current_schema() then 0 else 1 end,
      schemaname asc
    limit 1
  ),
  ''
);
SQL
)"
payments_holds_schema="$(psql_query "$PAYMENTS_DB_NAME" "$payments_holds_schema_sql" "$PG_USER" "$PG_PASSWORD")"
payments_holds_exists="f"
payments_holds_table_ref=""
if [[ -n "$payments_holds_schema" ]]; then
  payments_holds_exists="t"
  payments_holds_table_ref="\"${payments_holds_schema}\".driver_ride_fee_holds"
fi

payments_summary_sql=""
if [[ "$payments_holds_exists" == "t" ]]; then
  payments_summary_sql="$(cat <<SQL
select 'reserved_fee_holds_stale', count(*)::bigint
from ${payments_holds_table_ref}
where status = 'reserved'
  and updated_at < now() - make_interval(secs => ${RESERVED_FEE_HOLD_STALE_SECS});
SQL
)"
fi

matching_stale=0
matching_without_pending_offer_stale=0
pending_offers_stale=0
online_presence_stale=0
active_trips_without_fresh_live_state=0
active_trips_missing_driver=0
reserved_fee_holds_stale=0
ops_accounts=0
active_chat_accounts=0
ops_with_active_chat_devices=0
ops_active_chat_devices=0
ops_push_tokens=0
ops_push_devices_without_tokens=0
ops_push_client_device_aliases=0
ops_push_ready_accounts=0
ops_push_readiness_blocked=0

ops_accounts_file="$(mktemp)"
active_chat_accounts_file="$(mktemp)"
ops_active_device_rows_file="$(mktemp)"
ops_device_ids_file="$(mktemp)"
ops_push_token_device_ids_file="$(mktemp)"
all_push_token_device_ids_file="$(mktemp)"
ops_push_ready_accounts_file="$(mktemp)"
ops_push_devices_without_tokens_file="$(mktemp)"
ops_push_client_device_aliases_file="$(mktemp)"
cleanup_report_tmp() {
  rm -f \
    "$ops_accounts_file" \
    "$active_chat_accounts_file" \
    "$ops_active_device_rows_file" \
    "$ops_device_ids_file" \
    "$ops_push_token_device_ids_file" \
    "$all_push_token_device_ids_file" \
    "$ops_push_ready_accounts_file" \
    "$ops_push_devices_without_tokens_file" \
    "$ops_push_client_device_aliases_file"
}
trap cleanup_report_tmp EXIT

while IFS='|' read -r label count; do
  [[ -n "$label" ]] || continue
  case "$label" in
    matching_stale) matching_stale="$count" ;;
    matching_without_pending_offer_stale) matching_without_pending_offer_stale="$count" ;;
    pending_offers_stale) pending_offers_stale="$count" ;;
    online_presence_stale) online_presence_stale="$count" ;;
    active_trips_without_fresh_live_state) active_trips_without_fresh_live_state="$count" ;;
    active_trips_missing_driver) active_trips_missing_driver="$count" ;;
  esac
done < <(psql_query "$AUTH_DB_NAME" "$auth_summary_sql" "$PG_USER" "$PG_PASSWORD")

if [[ -n "$payments_summary_sql" ]]; then
  while IFS='|' read -r label count; do
    [[ -n "$label" ]] || continue
    case "$label" in
      reserved_fee_holds_stale) reserved_fee_holds_stale="$count" ;;
    esac
  done < <(psql_query "$PAYMENTS_DB_NAME" "$payments_summary_sql" "$PG_USER" "$PG_PASSWORD")
fi

ride_operator_allowed_roles_sql="$(sql_quoted_csv "${RIDE_OPERATOR_ALLOWED_ROLES[@]}")"

psql_query "$PAYMENTS_DB_NAME" "$(cat <<SQL
select distinct account_id
from roles
where role in (${ride_operator_allowed_roles_sql})
  and coalesce(account_id, '') <> ''
order by account_id;
SQL
)" "$PG_USER" "$PG_PASSWORD" > "$ops_accounts_file"
ops_accounts="$(wc -l < "$ops_accounts_file" | tr -d ' ')"

psql_query "$AUTH_DB_NAME" "$(cat <<'SQL'
select distinct account_id
from auth_chat_devices
where account_id is not null
  and btrim(account_id) <> ''
  and revoked_at is null
order by account_id;
SQL
)" "$PG_USER" "$PG_PASSWORD" > "$active_chat_accounts_file"
active_chat_accounts="$(wc -l < "$active_chat_accounts_file" | tr -d ' ')"
ops_with_active_chat_devices="$(comm -12 "$ops_accounts_file" "$active_chat_accounts_file" | wc -l | tr -d ' ')"
psql_query "$CHAT_DB_NAME" "select distinct device_id from push_tokens order by device_id;" "$PG_USER" "$PG_PASSWORD" > "$all_push_token_device_ids_file"

if (( ops_with_active_chat_devices > 0 )); then
  while IFS= read -r account_id; do
    [[ -n "$account_id" ]] || continue
    psql_query "$AUTH_DB_NAME" "select account_id || '|' || chat_device_id || '|' || client_device_id || '|' || to_char((last_seen_at at time zone 'UTC'), 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') from auth_chat_devices where revoked_at is null and account_id = '${account_id}' order by last_seen_at desc;" "$PG_USER" "$PG_PASSWORD"
  done < <(comm -12 "$ops_accounts_file" "$active_chat_accounts_file") > "$ops_active_device_rows_file"
  ops_active_chat_devices="$(grep -c '.' "$ops_active_device_rows_file" || true)"

  if [[ -s "$ops_active_device_rows_file" ]]; then
    awk -F'|' '{print $2}' "$ops_active_device_rows_file" | sort -u > "$ops_device_ids_file"
    ops_device_id_list="$(awk 'BEGIN { first = 1 } { if (!first) printf("','"); printf("%s", $0); first = 0 }' "$ops_device_ids_file")"
    if [[ -n "$ops_device_id_list" ]]; then
      psql_query "$CHAT_DB_NAME" "select distinct device_id from push_tokens where device_id in ('${ops_device_id_list}') order by device_id;" "$PG_USER" "$PG_PASSWORD" > "$ops_push_token_device_ids_file"
      ops_push_tokens="$(wc -l < "$ops_push_token_device_ids_file" | tr -d ' ')"
      ops_push_devices_without_tokens="$((ops_active_chat_devices - ops_push_tokens))"
      if [[ "$ops_push_devices_without_tokens" -lt 0 ]]; then
        ops_push_devices_without_tokens=0
      fi
      if [[ -s "$ops_push_token_device_ids_file" ]]; then
        awk -F'|' 'NR==FNR { seen[$1]=1; next } seen[$2] { print $1 }' \
          "$ops_push_token_device_ids_file" \
          "$ops_active_device_rows_file" \
          | sort -u > "$ops_push_ready_accounts_file"
        ops_push_ready_accounts="$(wc -l < "$ops_push_ready_accounts_file" | tr -d ' ')"
      fi
      : > "$ops_push_devices_without_tokens_file"
      while IFS='|' read -r account_id chat_device_id client_device_id last_seen_at; do
        [[ -n "$chat_device_id" ]] || continue
        if ! grep -Fxq "$chat_device_id" "$ops_push_token_device_ids_file"; then
          printf '%s|%s|%s|%s\n' \
            "$account_id" \
            "$chat_device_id" \
            "$client_device_id" \
            "$last_seen_at" >> "$ops_push_devices_without_tokens_file"
        fi
      done < "$ops_active_device_rows_file"
      : > "$ops_push_client_device_aliases_file"
      if [[ -s "$ops_push_devices_without_tokens_file" ]] && [[ -s "$all_push_token_device_ids_file" ]]; then
        while IFS='|' read -r account_id chat_device_id client_device_id last_seen_at; do
          [[ -n "$client_device_id" ]] || continue
          while IFS='|' read -r alias_account_id alias_chat_device_id alias_last_seen_at; do
            [[ -n "$alias_chat_device_id" ]] || continue
            if [[ "$alias_chat_device_id" == "$chat_device_id" ]]; then
              continue
            fi
            if grep -Fxq "$alias_chat_device_id" "$all_push_token_device_ids_file"; then
              printf '%s|%s|%s|%s|%s|%s\n' \
                "$account_id" \
                "$chat_device_id" \
                "$client_device_id" \
                "$alias_chat_device_id" \
                "$alias_account_id" \
                "$alias_last_seen_at" >> "$ops_push_client_device_aliases_file"
              break
            fi
          done < <(
            psql_query "$AUTH_DB_NAME" "select account_id || '|' || chat_device_id || '|' || to_char((last_seen_at at time zone 'UTC'), 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') from auth_chat_devices where revoked_at is null and client_device_id = '${client_device_id}' order by last_seen_at desc;" "$PG_USER" "$PG_PASSWORD"
          )
        done < "$ops_push_devices_without_tokens_file"
      fi
      ops_push_client_device_aliases="$(grep -c '.' "$ops_push_client_device_aliases_file" || true)"
    fi
  fi
fi

if (( fcm_server_key_missing > 0 )); then
  ops_push_readiness_blocked=1
fi
if (( ops_with_active_chat_devices > 0 )) && (( ops_push_tokens == 0 )); then
  ops_push_readiness_blocked=1
fi

findings_total=$((matching_stale + matching_without_pending_offer_stale + pending_offers_stale + online_presence_stale + active_trips_without_fresh_live_state + active_trips_missing_driver + reserved_fee_holds_stale + bff_service_unhealthy + payments_service_unhealthy + chat_service_unhealthy + fcm_server_key_missing + ops_push_readiness_blocked))

printf 'ride-report: auth_db=%s payments_db=%s chat_db=%s\n' "$AUTH_DB_NAME" "$PAYMENTS_DB_NAME" "$CHAT_DB_NAME"
printf 'ride-report: thresholds matching=%ss matching_no_offer=%ss pending_offer=%ss presence=%ss live=%ss fee_hold=%ss detail_limit=%s\n' \
  "$MATCHING_STALE_SECS" \
  "$MATCHING_NO_OFFER_STALE_SECS" \
  "$PENDING_OFFER_STALE_SECS" \
  "$DRIVER_PRESENCE_STALE_SECS" \
  "$LIVE_STATE_STALE_SECS" \
  "$RESERVED_FEE_HOLD_STALE_SECS" \
  "$DETAIL_LIMIT"

printf '\n[summary]\n'
printf 'bff_service_status=%s\n' "$bff_service_status"
printf 'bff_restart_count=%s\n' "$bff_restart_count"
printf 'payments_service_status=%s\n' "$payments_service_status"
printf 'payments_restart_count=%s\n' "$payments_restart_count"
printf 'chat_service_status=%s\n' "$chat_service_status"
printf 'chat_restart_count=%s\n' "$chat_restart_count"
printf 'fcm_server_key_configured=%s\n' "$((1 - fcm_server_key_missing))"
printf 'ops_accounts=%s\n' "$ops_accounts"
printf 'active_chat_accounts=%s\n' "$active_chat_accounts"
printf 'ops_with_active_chat_devices=%s\n' "$ops_with_active_chat_devices"
printf 'ops_active_chat_devices=%s\n' "$ops_active_chat_devices"
printf 'ops_push_tokens=%s\n' "$ops_push_tokens"
printf 'ops_push_devices_without_tokens=%s\n' "$ops_push_devices_without_tokens"
printf 'ops_push_client_device_aliases=%s\n' "$ops_push_client_device_aliases"
printf 'ops_push_ready_accounts=%s\n' "$ops_push_ready_accounts"
printf 'matching_stale=%s\n' "$matching_stale"
printf 'matching_without_pending_offer_stale=%s\n' "$matching_without_pending_offer_stale"
printf 'pending_offers_stale=%s\n' "$pending_offers_stale"
printf 'online_presence_stale=%s\n' "$online_presence_stale"
printf 'active_trips_without_fresh_live_state=%s\n' "$active_trips_without_fresh_live_state"
printf 'active_trips_missing_driver=%s\n' "$active_trips_missing_driver"
if [[ "$payments_holds_exists" == "t" ]]; then
  printf 'reserved_fee_holds_stale=%s\n' "$reserved_fee_holds_stale"
else
  printf 'reserved_fee_holds_stale=table_missing\n'
fi

if (( matching_stale > 0 )); then
  matching_rows="$(psql_query "$AUTH_DB_NAME" "$(cat <<SQL
select ride_id || '|' || status || '|' || extract(epoch from (now() - status_updated_at))::bigint
from auth_ride_trips
where status = 'matching'
  and status_updated_at < now() - make_interval(secs => ${MATCHING_STALE_SECS})
order by status_updated_at asc
limit ${DETAIL_LIMIT};
SQL
)" "$PG_USER" "$PG_PASSWORD")"
  emit_detail_section "matching_stale_details ride_id|status|age_seconds" "$matching_rows"
fi

if (( matching_without_pending_offer_stale > 0 )); then
  no_offer_rows="$(psql_query "$AUTH_DB_NAME" "$(cat <<SQL
select trip.ride_id || '|' || extract(epoch from (now() - trip.status_updated_at))::bigint
from auth_ride_trips trip
where trip.status = 'matching'
  and trip.status_updated_at < now() - make_interval(secs => ${MATCHING_NO_OFFER_STALE_SECS})
  and not exists (
    select 1
    from auth_ride_dispatch_offers offers
    where offers.ride_id = trip.ride_id
      and offers.status = 'pending'
  )
order by trip.status_updated_at asc
limit ${DETAIL_LIMIT};
SQL
)" "$PG_USER" "$PG_PASSWORD")"
  emit_detail_section "matching_without_pending_offer_stale_details ride_id|age_seconds" "$no_offer_rows"
fi

if (( pending_offers_stale > 0 )); then
  offer_rows="$(psql_query "$AUTH_DB_NAME" "$(cat <<SQL
select offer_id || '|' || ride_id || '|' || driver_account_id || '|' || extract(epoch from (now() - offered_at))::bigint
from auth_ride_dispatch_offers
where status = 'pending'
  and offered_at < now() - make_interval(secs => ${PENDING_OFFER_STALE_SECS})
order by offered_at asc
limit ${DETAIL_LIMIT};
SQL
)" "$PG_USER" "$PG_PASSWORD")"
  emit_detail_section "pending_offers_stale_details offer_id|ride_id|driver_account_id|age_seconds" "$offer_rows"
fi

if (( online_presence_stale > 0 )); then
  stale_driver_rows="$(psql_query "$AUTH_DB_NAME" "$(cat <<SQL
select driver_account_id || '|' || extract(epoch from (now() - last_seen_at))::bigint
from auth_ride_driver_presence
where availability_status = 'online'
  and last_seen_at < now() - make_interval(secs => ${DRIVER_PRESENCE_STALE_SECS})
order by last_seen_at asc
limit ${DETAIL_LIMIT};
SQL
)" "$PG_USER" "$PG_PASSWORD")"
  emit_detail_section "online_presence_stale_details driver_account_id|age_seconds" "$stale_driver_rows"
fi

if (( active_trips_without_fresh_live_state > 0 )); then
  live_rows="$(psql_query "$AUTH_DB_NAME" "$(cat <<SQL
select trip.ride_id || '|' || trip.status || '|' || coalesce(extract(epoch from (now() - coalesce(live.last_location_at, live.updated_at)))::bigint::text, 'missing')
from auth_ride_trips trip
left join auth_ride_trip_live_state live
  on live.ride_id = trip.ride_id
where trip.status in ('driver_assigned', 'driver_arriving', 'driver_arrived', 'trip_started', 'trip_in_progress')
  and (
    live.ride_id is null
    or coalesce(live.last_location_at, live.updated_at)
      < now() - make_interval(secs => ${LIVE_STATE_STALE_SECS})
  )
order by trip.status_updated_at asc
limit ${DETAIL_LIMIT};
SQL
)" "$PG_USER" "$PG_PASSWORD")"
  emit_detail_section "active_trips_without_fresh_live_state_details ride_id|status|live_age_seconds_or_missing" "$live_rows"
fi

if (( active_trips_missing_driver > 0 )); then
  missing_driver_rows="$(psql_query "$AUTH_DB_NAME" "$(cat <<SQL
select ride_id || '|' || status || '|' || extract(epoch from (now() - status_updated_at))::bigint
from auth_ride_trips
where status in ('driver_assigned', 'driver_arriving', 'driver_arrived', 'trip_started', 'trip_in_progress')
  and coalesce(driver_account_id, '') = ''
order by status_updated_at asc
limit ${DETAIL_LIMIT};
SQL
)" "$PG_USER" "$PG_PASSWORD")"
  emit_detail_section "active_trips_missing_driver_details ride_id|status|age_seconds" "$missing_driver_rows"
fi

if [[ "$payments_holds_exists" == "t" ]] && (( reserved_fee_holds_stale > 0 )); then
  hold_rows="$(psql_query "$PAYMENTS_DB_NAME" "$(cat <<SQL
select ride_id || '|' || wallet_id || '|' || amount_cents || '|' || extract(epoch from (now() - updated_at))::bigint
from ${payments_holds_table_ref}
where status = 'reserved'
  and updated_at < now() - make_interval(secs => ${RESERVED_FEE_HOLD_STALE_SECS})
order by updated_at asc
limit ${DETAIL_LIMIT};
SQL
)" "$PG_USER" "$PG_PASSWORD")"
  emit_detail_section "reserved_fee_holds_stale_details ride_id|wallet_id|amount_cents|age_seconds" "$hold_rows"
fi

if (( bff_service_unhealthy > 0 || payments_service_unhealthy > 0 || chat_service_unhealthy > 0 )); then
  service_rows="$(cat <<EOF
bff|${bff_service_status}|${bff_restart_count}|${bff_container_id:-missing}
payments|${payments_service_status}|${payments_restart_count}|${payments_container_id:-missing}
chat|${chat_service_status}|${chat_restart_count}|${chat_container_id:-missing}
EOF
)"
  emit_detail_section "service_health_details service|status|restart_count|container_id" "$service_rows"
fi

if (( fcm_server_key_missing > 0 )); then
  emit_detail_section "push_config_details key|status" "FCM_SERVER_KEY|missing"
fi

if (( ops_with_active_chat_devices > 0 )); then
  ops_device_rows="$(awk -F'|' 'NR <= limit {print $1 "|" $2 "|" $3 "|" $4}' limit="${DETAIL_LIMIT}" "$ops_active_device_rows_file")"
  emit_detail_section "ops_active_chat_device_details account_id|chat_device_id|client_device_id|last_seen_at_utc" "$ops_device_rows"
fi

if (( ops_push_devices_without_tokens > 0 )); then
  missing_push_rows="$(head -n "${DETAIL_LIMIT}" "$ops_push_devices_without_tokens_file")"
  emit_detail_section "ops_push_devices_without_tokens_details account_id|chat_device_id|client_device_id|last_seen_at_utc" "$missing_push_rows"
fi

if (( ops_push_client_device_aliases > 0 )); then
  alias_push_rows="$(head -n "${DETAIL_LIMIT}" "$ops_push_client_device_aliases_file")"
  emit_detail_section "ops_push_client_device_alias_details missing_account_id|missing_chat_device_id|client_device_id|token_chat_device_id|token_account_id|token_last_seen_at_utc" "$alias_push_rows"
fi

printf '\nride-report: findings_total=%s\n' "$findings_total"
if is_true_like "$FAIL_ON_FINDINGS" && (( findings_total > 0 )); then
  echo "ride-report: findings detected and RIDE_REPORT_FAIL_ON_FINDINGS=1." >&2
  exit 1
fi
