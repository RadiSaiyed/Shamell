#!/usr/bin/env bash
set -euo pipefail

export DB_URL=${DB_URL:-sqlite+pysqlite:////tmp/stays.db}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

source .venv311/bin/activate

echo "[migrate] Using DB_URL=$DB_URL"

python - << 'PY'
import os, sys
from sqlalchemy import create_engine, inspect

db_url = os.environ.get('DB_URL', 'sqlite+pysqlite:////tmp/stays.db')
engine = create_engine(db_url)
insp = inspect(engine)
tables = set(insp.get_table_names())

# If any of our target tables already exist, just stamp head to avoid CREATE errors
targets = {"operators", "operator_tokens", "idempotency", "listings", "bookings"}
if tables & targets:
    print('[migrate] Existing tables found:', ','.join(sorted(tables & targets)))
    # Stamp head; actual migrations should be applied previously/outside
    os.execvp('alembic', ['alembic','-c','apps/stays/alembic.ini','stamp','head'])
else:
    os.execvp('alembic', ['alembic','-c','apps/stays/alembic.ini','upgrade','head'])
PY

echo "[migrate] Done"
