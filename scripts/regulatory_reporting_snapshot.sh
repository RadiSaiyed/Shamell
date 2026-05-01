#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_DEV_ENV_FILE="${ROOT_DIR}/.env"
DEFAULT_DEV_COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
DEFAULT_OPS_ENV_FILE="${ROOT_DIR}/ops/pi/.env"
DEFAULT_OPS_COMPOSE_FILE="${ROOT_DIR}/ops/pi/docker-compose.postgres.yml"
BOOTSTRAP_SQL="${ROOT_DIR}/ops/pi/postgres/regulatory_reporting_bootstrap.sql"
SOURCE_VIEWS_SQL="${ROOT_DIR}/services_rs/bff_gateway/migrations/0099_bff_auth_regulatory_reporting_views.sql"

if [[ -z "${ENV_FILE:-}" ]]; then
  if [[ -f "${DEFAULT_DEV_ENV_FILE}" ]]; then
    ENV_FILE="${DEFAULT_DEV_ENV_FILE}"
  else
    ENV_FILE="${DEFAULT_OPS_ENV_FILE}"
  fi
fi

if [[ -z "${COMPOSE_FILE:-}" ]]; then
  if [[ "${ENV_FILE}" == "${DEFAULT_DEV_ENV_FILE}" ]]; then
    COMPOSE_FILE="${DEFAULT_DEV_COMPOSE_FILE}"
  else
    COMPOSE_FILE="${DEFAULT_OPS_COMPOSE_FILE}"
  fi
fi

SNAPSHOT_REGISTERED=0
SNAPSHOT_READY=0
SNAPSHOT_ID=""
TARGET_DB_NAME=""

log() {
  printf '[regulatory-snapshot] %s\n' "$*"
}

fail() {
  printf '[regulatory-snapshot][error] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

read_env() {
  local key="$1"
  if [[ ! -f "${ENV_FILE}" ]]; then
    return 0
  fi
  local value
  value="$(awk -F= -v k="$key" '$1==k{v=substr($0, index($0,$2))} END{print v}' "${ENV_FILE}")"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "$value"
}

config_value() {
  local key="$1"
  local default_value="${2:-}"
  local runtime_value="${!key-}"
  if [[ -n "${runtime_value}" ]]; then
    printf '%s' "${runtime_value}"
    return 0
  fi
  local file_value
  file_value="$(read_env "$key")"
  if [[ -n "${file_value}" ]]; then
    printf '%s' "${file_value}"
    return 0
  fi
  printf '%s' "${default_value}"
}

compose() {
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" "$@"
}

db_name_from_url() {
  local url="$1"
  local db_name="${url##*/}"
  db_name="${db_name%%\?*}"
  printf '%s' "$db_name"
}

require_safe_identifier() {
  local value="$1"
  local name="$2"
  [[ "${value}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail "${name} must be a safe postgres identifier"
}

sql_literal() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf '%s' "$value"
}

sha256_text() {
  local value="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$value" | sha256sum | awk '{print $1}'
    return 0
  fi
  printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return 0
  fi
  shasum -a 256 "$path" | awk '{print $1}'
}

compose_psql() {
  local db_name="$1"
  shift
  compose exec -T -e "PGPASSWORD=${PG_PASSWORD}" db \
    psql -X -v ON_ERROR_STOP=1 -U "${PG_USER}" -d "${db_name}" "$@"
}

compose_query_scalar() {
  local db_name="$1"
  local sql="$2"
  compose_psql "${db_name}" -At -c "${sql}"
}

mark_snapshot_failed() {
  local exit_code="$1"
  if [[ "${exit_code}" -eq 0 || "${SNAPSHOT_REGISTERED}" != "1" || "${SNAPSHOT_READY}" == "1" ]]; then
    return 0
  fi
  set +e
  compose_psql "${TARGET_DB_NAME}" \
    -v snapshot_id="${SNAPSHOT_ID}" \
    -v error_detail="snapshot job failed before completion" <<'SQL' >/dev/null 2>&1
UPDATE regulatory_snapshot.snapshot_runs
SET
    status = 'failed',
    completed_at = NOW(),
    error_detail = :'error_detail'
WHERE snapshot_id = :'snapshot_id'
  AND status = 'loading';
SQL
  set -e
}

trap 'mark_snapshot_failed "$?"' EXIT

require_cmd awk
require_cmd date
require_cmd docker
require_cmd mkdir
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  fail "missing required command: sha256sum or shasum"
fi

[[ -f "${ENV_FILE}" ]] || fail "env file not found: ${ENV_FILE}"
[[ -f "${COMPOSE_FILE}" ]] || fail "compose file not found: ${COMPOSE_FILE}"
[[ -f "${BOOTSTRAP_SQL}" ]] || fail "bootstrap sql not found: ${BOOTSTRAP_SQL}"
[[ -f "${SOURCE_VIEWS_SQL}" ]] || fail "source views sql not found: ${SOURCE_VIEWS_SQL}"

PG_USER="$(config_value POSTGRES_USER)"
PG_PASSWORD="$(config_value POSTGRES_PASSWORD)"
SOURCE_DB_URL="$(config_value DB_URL)"
TARGET_DB_URL="$(config_value REGULATORY_REPORTING_DB_URL)"
REGULATORY_SNAPSHOT_SALT="$(config_value REGULATORY_REPORTING_SNAPSHOT_SALT)"
REGULATOR_ROLE="$(config_value REGULATOR_RO_USERNAME regulator_ro)"
REGULATOR_PASSWORD="$(config_value REGULATOR_RO_PASSWORD)"
MANIFEST_DIR="$(config_value REGULATORY_SNAPSHOT_MANIFEST_DIR "${ROOT_DIR}/.artifacts/regulatory-snapshots")"
SIGNING_KEY_FILE="$(config_value REGULATORY_SNAPSHOT_SIGNING_KEY_FILE)"
EXPORTED_BY="${REGULATORY_SNAPSHOT_EXPORTED_BY:-${USER:-unknown}}"
SNAPSHOT_ID="${REGULATORY_SNAPSHOT_ID:-regsnap_$(date -u +%Y%m%dT%H%M%SZ)}"

[[ -n "${PG_USER}" ]] || fail "POSTGRES_USER must be set"
[[ -n "${PG_PASSWORD}" ]] || fail "POSTGRES_PASSWORD must be set"
[[ -n "${SOURCE_DB_URL}" ]] || fail "DB_URL must be set"
[[ -n "${TARGET_DB_URL}" ]] || fail "REGULATORY_REPORTING_DB_URL must be set"
[[ -n "${REGULATORY_SNAPSHOT_SALT}" ]] || fail "REGULATORY_REPORTING_SNAPSHOT_SALT must be set"
[[ -n "${REGULATOR_ROLE}" ]] || fail "REGULATOR_RO_USERNAME must be set"
[[ -n "${REGULATOR_PASSWORD}" ]] || fail "REGULATOR_RO_PASSWORD must be set"
require_safe_identifier "${REGULATOR_ROLE}" "REGULATOR_RO_USERNAME"

if [[ -n "${SIGNING_KEY_FILE}" && ! -f "${SIGNING_KEY_FILE}" ]]; then
  fail "REGULATORY_SNAPSHOT_SIGNING_KEY_FILE does not exist: ${SIGNING_KEY_FILE}"
fi
if [[ -n "${SIGNING_KEY_FILE}" ]]; then
  require_cmd openssl
fi

SOURCE_DB_NAME="$(db_name_from_url "${SOURCE_DB_URL}")"
TARGET_DB_NAME="$(db_name_from_url "${TARGET_DB_URL}")"
[[ -n "${SOURCE_DB_NAME}" ]] || fail "could not parse source database name from DB_URL"
[[ -n "${TARGET_DB_NAME}" ]] || fail "could not parse target database name from REGULATORY_REPORTING_DB_URL"
require_safe_identifier "${SOURCE_DB_NAME}" "DB_URL database name"
require_safe_identifier "${TARGET_DB_NAME}" "REGULATORY_REPORTING_DB_URL database name"

mkdir -p "${MANIFEST_DIR}"
umask 077

if [[ "$(compose_query_scalar postgres "SELECT 1 FROM pg_database WHERE datname = '$(sql_literal "${TARGET_DB_NAME}")'")" != "1" ]]; then
  log "creating target database ${TARGET_DB_NAME}"
  compose_psql postgres -c "CREATE DATABASE ${TARGET_DB_NAME}"
fi

log "refreshing source regulatory views in ${SOURCE_DB_NAME}"
compose_psql "${SOURCE_DB_NAME}" < "${SOURCE_VIEWS_SQL}"

log "bootstrapping ${TARGET_DB_NAME} schemas and regulator role"
compose_psql "${TARGET_DB_NAME}" \
  -v regulator_role="${REGULATOR_ROLE}" \
  -v regulator_password="${REGULATOR_PASSWORD}" < "${BOOTSTRAP_SQL}"

SOURCE_CUTOFF_AT="$(compose_query_scalar "${SOURCE_DB_NAME}" "SELECT NOW()::text")"
SALT_FINGERPRINT="$(sha256_text "${REGULATORY_SNAPSHOT_SALT}")"

log "registering snapshot ${SNAPSHOT_ID}"
compose_psql "${TARGET_DB_NAME}" \
  -v snapshot_id="${SNAPSHOT_ID}" \
  -v source_database="${SOURCE_DB_NAME}" \
  -v snapshot_cutoff_at="${SOURCE_CUTOFF_AT}" \
  -v salt_fingerprint="${SALT_FINGERPRINT}" \
  -v exported_by="${EXPORTED_BY}" <<'SQL'
BEGIN;
DELETE FROM regulatory_snapshot.trips WHERE snapshot_id = :'snapshot_id';
DELETE FROM regulatory_snapshot.drivers WHERE snapshot_id = :'snapshot_id';
DELETE FROM regulatory_snapshot.fares WHERE snapshot_id = :'snapshot_id';
DELETE FROM regulatory_snapshot.incidents WHERE snapshot_id = :'snapshot_id';
DELETE FROM regulatory_snapshot.audit_log WHERE snapshot_id = :'snapshot_id';
INSERT INTO regulatory_snapshot.snapshot_runs (
    snapshot_id,
    source_database,
    snapshot_cutoff_at,
    salt_fingerprint,
    status,
    exported_by,
    started_at,
    completed_at,
    error_detail
)
VALUES (
    :'snapshot_id',
    :'source_database',
    :'snapshot_cutoff_at'::timestamptz,
    :'salt_fingerprint',
    'loading',
    :'exported_by',
    NOW(),
    NULL,
    NULL
)
ON CONFLICT (snapshot_id) DO UPDATE
SET
    source_database = EXCLUDED.source_database,
    snapshot_cutoff_at = EXCLUDED.snapshot_cutoff_at,
    salt_fingerprint = EXCLUDED.salt_fingerprint,
    status = 'loading',
    exported_by = EXCLUDED.exported_by,
    started_at = NOW(),
    completed_at = NULL,
    trip_rows = 0,
    driver_rows = 0,
    fare_rows = 0,
    incident_rows = 0,
    audit_rows = 0,
    manifest_path = NULL,
    manifest_sha256 = NULL,
    manifest_signature_path = NULL,
    error_detail = NULL;
COMMIT;
SQL
SNAPSHOT_REGISTERED=1

copy_view_to_table() {
  local source_view="$1"
  local target_table="$2"
  local snapshot_sql
  local salt_sql
  snapshot_sql="$(sql_literal "${SNAPSHOT_ID}")"
  salt_sql="$(sql_literal "${REGULATORY_SNAPSHOT_SALT}")"
  log "copying ${source_view} -> ${target_table}"
  compose exec -T -e "PGPASSWORD=${PG_PASSWORD}" db \
    psql -X -q -v ON_ERROR_STOP=1 -U "${PG_USER}" -d "${SOURCE_DB_NAME}" \
    -c "SET app.reg_reporting_salt = '${salt_sql}'; COPY (SELECT '${snapshot_sql}' AS snapshot_id, * FROM regulatory_reporting.${source_view}) TO STDOUT WITH CSV HEADER" \
  | compose exec -T -e "PGPASSWORD=${PG_PASSWORD}" db \
    psql -X -q -v ON_ERROR_STOP=1 -U "${PG_USER}" -d "${TARGET_DB_NAME}" \
    -c "COPY regulatory_snapshot.${target_table} FROM STDIN WITH CSV HEADER"
}

copy_view_to_table "vw_reg_trips" "trips"
copy_view_to_table "vw_reg_drivers" "drivers"
copy_view_to_table "vw_reg_fares" "fares"
copy_view_to_table "vw_reg_incidents" "incidents"
copy_view_to_table "vw_reg_audit_log" "audit_log"

trip_rows="$(compose_query_scalar "${TARGET_DB_NAME}" "SELECT COUNT(*) FROM regulatory_snapshot.trips WHERE snapshot_id = '$(sql_literal "${SNAPSHOT_ID}")'")"
driver_rows="$(compose_query_scalar "${TARGET_DB_NAME}" "SELECT COUNT(*) FROM regulatory_snapshot.drivers WHERE snapshot_id = '$(sql_literal "${SNAPSHOT_ID}")'")"
fare_rows="$(compose_query_scalar "${TARGET_DB_NAME}" "SELECT COUNT(*) FROM regulatory_snapshot.fares WHERE snapshot_id = '$(sql_literal "${SNAPSHOT_ID}")'")"
incident_rows="$(compose_query_scalar "${TARGET_DB_NAME}" "SELECT COUNT(*) FROM regulatory_snapshot.incidents WHERE snapshot_id = '$(sql_literal "${SNAPSHOT_ID}")'")"
audit_rows="$(compose_query_scalar "${TARGET_DB_NAME}" "SELECT COUNT(*) FROM regulatory_snapshot.audit_log WHERE snapshot_id = '$(sql_literal "${SNAPSHOT_ID}")'")"

manifest_path="${MANIFEST_DIR}/${SNAPSHOT_ID}.manifest.json"
signature_path=""
generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "${manifest_path}" <<EOF
{
  "snapshot_id": "${SNAPSHOT_ID}",
  "generated_at_utc": "${generated_at_utc}",
  "source_database": "${SOURCE_DB_NAME}",
  "target_database": "${TARGET_DB_NAME}",
  "snapshot_cutoff_at": "${SOURCE_CUTOFF_AT}",
  "salt_fingerprint_sha256": "${SALT_FINGERPRINT}",
  "exported_by": "${EXPORTED_BY}",
  "row_counts": {
    "trips": ${trip_rows},
    "drivers": ${driver_rows},
    "fares": ${fare_rows},
    "incidents": ${incident_rows},
    "audit_log": ${audit_rows}
  }
}
EOF

manifest_sha256="$(sha256_file "${manifest_path}")"
if [[ -n "${SIGNING_KEY_FILE}" ]]; then
  signature_path="${MANIFEST_DIR}/${SNAPSHOT_ID}.manifest.sig"
  openssl dgst -sha256 -sign "${SIGNING_KEY_FILE}" -out "${signature_path}" "${manifest_path}"
fi

log "marking snapshot ${SNAPSHOT_ID} ready"
compose_psql "${TARGET_DB_NAME}" \
  -v snapshot_id="${SNAPSHOT_ID}" \
  -v trip_rows="${trip_rows}" \
  -v driver_rows="${driver_rows}" \
  -v fare_rows="${fare_rows}" \
  -v incident_rows="${incident_rows}" \
  -v audit_rows="${audit_rows}" \
  -v manifest_path="${manifest_path}" \
  -v manifest_sha256="${manifest_sha256}" \
  -v signature_path="${signature_path}" <<'SQL'
UPDATE regulatory_snapshot.snapshot_runs
SET
    trip_rows = :'trip_rows'::bigint,
    driver_rows = :'driver_rows'::bigint,
    fare_rows = :'fare_rows'::bigint,
    incident_rows = :'incident_rows'::bigint,
    audit_rows = :'audit_rows'::bigint,
    manifest_path = NULLIF(:'manifest_path', ''),
    manifest_sha256 = NULLIF(:'manifest_sha256', ''),
    manifest_signature_path = NULLIF(:'signature_path', ''),
    status = 'ready',
    completed_at = NOW(),
    error_detail = NULL
WHERE snapshot_id = :'snapshot_id';
SQL
SNAPSHOT_READY=1

log "ok snapshot=${SNAPSHOT_ID} trips=${trip_rows} drivers=${driver_rows} fares=${fare_rows} incidents=${incident_rows} audit=${audit_rows}"
log "manifest=${manifest_path}"
if [[ -n "${signature_path}" ]]; then
  log "signature=${signature_path}"
fi
