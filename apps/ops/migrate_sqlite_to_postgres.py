from __future__ import annotations

import os
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Iterable

from sqlalchemy import MetaData, Table, create_engine, inspect, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.engine import Engine


CHUNK_SIZE = int(os.getenv("MIGRATE_CHUNK_SIZE", "750"))
SKIP_TABLES = {
    "sqlite_sequence",
    "alembic_version",
}


@dataclass(frozen=True)
class _DbPair:
    label: str
    sqlite_path: str
    pg_url: str


def _log(msg: str) -> None:
    print(msg, flush=True)


def _parse_dt(value: str) -> datetime | None:
    v = (value or "").strip()
    if not v:
        return None
    if v.endswith("Z"):
        v = v[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(v)
    except Exception:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def _coerce_value(col, value: Any) -> Any:
    if value is None:
        return None
    try:
        tname = getattr(getattr(col, "type", None), "__class__", type("x", (), {})).__name__.lower()
    except Exception:
        tname = ""

    if isinstance(value, str) and "datetime" in tname:
        dt = _parse_dt(value)
        return dt if dt is not None else value
    if "boolean" in tname and isinstance(value, (int, float)):
        return bool(int(value))
    if ("integer" in tname or "bigint" in tname) and isinstance(value, str):
        s = value.strip()
        if s.isdigit() or (s.startswith("-") and s[1:].isdigit()):
            try:
                return int(s)
            except Exception:
                return value
    return value


def _sqlite_tables(conn: sqlite3.Connection) -> list[str]:
    cur = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
    out = []
    for (name,) in cur.fetchall():
        name = (name or "").strip()
        if not name:
            continue
        if name in SKIP_TABLES:
            continue
        out.append(name)
    return sorted(set(out))


def _sqlite_columns(conn: sqlite3.Connection, table: str) -> list[str]:
    cur = conn.execute(f"PRAGMA table_info('{table}')")
    cols = []
    for row in cur.fetchall():
        # row: (cid, name, type, notnull, dflt_value, pk)
        name = str(row[1] or "").strip()
        if name:
            cols.append(name)
    return cols


def _reflect_tables(engine: Engine, names: Iterable[str]) -> dict[str, Table]:
    md = MetaData()
    out: dict[str, Table] = {}
    for name in names:
        out[name] = Table(name, md, autoload_with=engine)
    return out


def _toposort_tables(tables: dict[str, Table]) -> list[str]:
    # Order parent tables before children using reflected FK constraints.
    names = sorted(tables.keys())
    deps: dict[str, set[str]] = {n: set() for n in names}  # child -> parents
    rdeps: dict[str, set[str]] = {n: set() for n in names}  # parent -> children

    for child, t in tables.items():
        try:
            for fk in t.foreign_key_constraints:
                for elem in fk.elements:
                    parent = getattr(getattr(elem, "column", None), "table", None)
                    if parent is None:
                        continue
                    parent_name = getattr(parent, "name", "")
                    if parent_name and parent_name in tables and parent_name != child:
                        deps[child].add(parent_name)
                        rdeps[parent_name].add(child)
        except Exception:
            continue

    ready = [n for n in names if not deps[n]]
    out: list[str] = []
    while ready:
        n = ready.pop(0)
        out.append(n)
        for child in sorted(rdeps.get(n, set())):
            deps[child].discard(n)
            if not deps[child]:
                ready.append(child)
    if len(out) != len(names):
        # Cycle or reflection failure; fall back to stable order.
        return names
    return out


def _reset_sequences(engine: Engine) -> None:
    """
    If we inserted explicit values into SERIAL/IDENTITY columns, reset sequences so
    subsequent inserts do not collide.
    """
    insp = inspect(engine)
    tables = insp.get_table_names(schema="public")
    with engine.begin() as conn:
        for t in tables:
            cols = insp.get_columns(t, schema="public")
            for col in cols:
                name = col.get("name")
                default = str(col.get("default") or "")
                if not name or "nextval(" not in default:
                    continue
                conn.execute(
                    text(
                        f"SELECT setval(pg_get_serial_sequence('{t}', '{name}'), "
                        f"COALESCE((SELECT MAX({name}) FROM {t}), 1), true)"
                    )
                )


def _migrate_pair(pair: _DbPair) -> None:
    sqlite_path = pair.sqlite_path
    if not sqlite_path or not os.path.exists(sqlite_path):
        _log(f"[skip] {pair.label}: sqlite not found at {sqlite_path}")
        return

    _log(f"[start] {pair.label}: migrating sqlite -> postgres")

    sqlite_conn = sqlite3.connect(sqlite_path)
    sqlite_conn.row_factory = sqlite3.Row

    pg_engine = create_engine(pair.pg_url, future=True, pool_pre_ping=True)
    pg_insp = inspect(pg_engine)
    pg_tables = set(pg_insp.get_table_names(schema="public"))

    src_tables = _sqlite_tables(sqlite_conn)
    target_tables = [t for t in src_tables if t in pg_tables and t not in SKIP_TABLES]
    missing = [t for t in src_tables if t not in pg_tables and t not in SKIP_TABLES]
    if missing:
        _log(f"[warn] {pair.label}: {len(missing)} sqlite tables missing in postgres (skipping): {', '.join(missing[:10])}")

    if not target_tables:
        _log(f"[done] {pair.label}: nothing to migrate (no matching tables)")
        return

    reflected = _reflect_tables(pg_engine, target_tables)
    ordered = _toposort_tables(reflected)

    for table_name in ordered:
        pg_table = reflected[table_name]
        src_cols = _sqlite_columns(sqlite_conn, table_name)
        if not src_cols:
            continue
        pg_cols = {c.name: c for c in pg_table.columns}
        common = [c for c in src_cols if c in pg_cols]
        if not common:
            continue

        _log(f"[table] {pair.label}.{table_name}: columns={len(common)}")
        sel = "SELECT " + ", ".join([f'"{c}"' for c in common]) + f' FROM "{table_name}"'
        cur = sqlite_conn.execute(sel)

        inserted = 0
        while True:
            rows = cur.fetchmany(CHUNK_SIZE)
            if not rows:
                break
            payload = []
            for r in rows:
                item = {}
                for c in common:
                    item[c] = _coerce_value(pg_cols[c], r[c])
                payload.append(item)

            stmt = pg_insert(pg_table).values(payload).on_conflict_do_nothing()
            with pg_engine.begin() as pg_conn:
                pg_conn.execute(stmt)
            inserted += len(payload)
        _log(f"[table] {pair.label}.{table_name}: migrated_rows={inserted}")

    try:
        _reset_sequences(pg_engine)
    except Exception:
        # Best-effort; do not fail migration if sequence reset is not supported.
        pass

    sqlite_conn.close()
    _log(f"[done] {pair.label}: migration complete")


def main() -> int:
    pairs: list[_DbPair] = []

    core_sqlite = os.getenv("MIGRATE_SQLITE_CORE_PATH", "")
    chat_sqlite = os.getenv("MIGRATE_SQLITE_CHAT_PATH", "")
    pay_sqlite = os.getenv("MIGRATE_SQLITE_PAYMENTS_PATH", "")

    core_pg = os.getenv("MIGRATE_PG_CORE_URL") or os.getenv("DB_URL") or ""
    chat_pg = os.getenv("MIGRATE_PG_CHAT_URL") or os.getenv("CHAT_DB_URL") or ""
    pay_pg = os.getenv("MIGRATE_PG_PAYMENTS_URL") or os.getenv("PAYMENTS_DB_URL") or ""

    if core_sqlite and core_pg:
        pairs.append(_DbPair(label="core", sqlite_path=core_sqlite, pg_url=core_pg))
    if chat_sqlite and chat_pg:
        pairs.append(_DbPair(label="chat", sqlite_path=chat_sqlite, pg_url=chat_pg))
    if pay_sqlite and pay_pg:
        pairs.append(_DbPair(label="payments", sqlite_path=pay_sqlite, pg_url=pay_pg))

    if not pairs:
        _log("[error] no migration pairs configured (missing env vars)")
        return 2

    for pair in pairs:
        _migrate_pair(pair)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
