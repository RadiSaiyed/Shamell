#!/usr/bin/env bash
set -euo pipefail

is_safe_ident() {
  local v="$1"
  [[ "$v" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

create_db() {
  local db="$1"
  if ! is_safe_ident "$db"; then
    echo "Invalid database name: ${db}" >&2
    exit 1
  fi
  local exists
  exists="$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${db}'" || true)"
  exists="$(echo "${exists:-}" | tr -d '[:space:]')"
  if [[ "$exists" == "1" ]]; then
    echo "Database exists: ${db}"
    return 0
  fi
  echo "Creating database: ${db}"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "CREATE DATABASE ${db};"
}

create_db "${POSTGRES_DB_CORE:-shamell_core}"
create_db "${POSTGRES_DB_CHAT:-shamell_chat}"
create_db "${POSTGRES_DB_PAYMENTS:-shamell_payments}"

