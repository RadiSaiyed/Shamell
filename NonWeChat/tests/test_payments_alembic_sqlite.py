import os
import sqlite3
import subprocess
import sys
import tempfile


def test_payments_alembic_upgrade_sqlite_uses_current_timestamp_default():
    """
    Regression: Alembic migrations must run on SQLite (Pi/staging) and must not
    use Postgres-only defaults like NOW().
    """
    with tempfile.TemporaryDirectory() as td:
        db_path = os.path.join(td, "payments.db")
        db_url = f"sqlite+pysqlite:///{db_path}"

        env = os.environ.copy()
        env.update(
            {
                "ENV": "test",
                "PAYMENTS_DB_URL": db_url,
            }
        )

        # Run migrations in a subprocess so Alembic's logging config does not
        # mutate the pytest process (it can reset handlers used by other tests).
        repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        proc = subprocess.run(
            [
                sys.executable,
                "-m",
                "alembic",
                "-c",
                "apps/payments/alembic.ini",
                "upgrade",
                "head",
            ],
            cwd=repo_root,
            env=env,
            text=True,
            capture_output=True,
        )
        assert proc.returncode == 0, f"alembic failed: {proc.stderr.strip()}"

        con = sqlite3.connect(db_path)
        try:
            for table in ("txns", "idempotency"):
                row = con.execute(
                    "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                    (table,),
                ).fetchone()
                assert row and row[0]
                ddl = row[0].upper()
                assert "NOW()" not in ddl
                assert "CURRENT_TIMESTAMP" in ddl
        finally:
            con.close()
