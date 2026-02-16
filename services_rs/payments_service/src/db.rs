use sqlx::postgres::{PgPool, PgPoolOptions};

fn table_name(schema: &Option<String>, name: &str) -> String {
    match schema {
        Some(s) => format!("{s}.{name}"),
        None => name.to_string(),
    }
}

pub async fn connect(db_url: &str) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(10)
        .connect(db_url)
        .await
}

pub async fn ensure_schema(pool: &PgPool, db_schema: &Option<String>) -> Result<(), sqlx::Error> {
    if let Some(schema) = db_schema {
        let ddl = format!("CREATE SCHEMA IF NOT EXISTS {schema}");
        let _ = sqlx::query(&ddl).execute(pool).await;
    }

    let users = table_name(db_schema, "users");
    let wallets = table_name(db_schema, "wallets");
    let txns = table_name(db_schema, "txns");
    let ledger = table_name(db_schema, "ledger_entries");
    let idempotency = table_name(db_schema, "idempotency");
    let favorites = table_name(db_schema, "favorites");
    let requests = table_name(db_schema, "payment_requests");
    let aliases = table_name(db_schema, "aliases");
    let roles = table_name(db_schema, "roles");

    let ddls = [
        format!(
            "CREATE TABLE IF NOT EXISTS {users} (\
             id VARCHAR(36) PRIMARY KEY,\
             account_id VARCHAR(64) UNIQUE,\
             phone VARCHAR(32) UNIQUE,\
             kyc_level INTEGER NOT NULL DEFAULT 0\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {wallets} (\
             id VARCHAR(36) PRIMARY KEY,\
             user_id VARCHAR(36) NOT NULL UNIQUE,\
             balance_cents BIGINT NOT NULL DEFAULT 0,\
             currency VARCHAR(3) NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {txns} (\
             id VARCHAR(36) PRIMARY KEY,\
             from_wallet_id VARCHAR(36),\
             to_wallet_id VARCHAR(36) NOT NULL,\
             amount_cents BIGINT NOT NULL,\
             kind VARCHAR(32) NOT NULL,\
             fee_cents BIGINT NOT NULL DEFAULT 0,\
             created_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {ledger} (\
             id VARCHAR(36) PRIMARY KEY,\
             wallet_id VARCHAR(36),\
             amount_cents BIGINT NOT NULL,\
             txn_id VARCHAR(36),\
             description VARCHAR(255),\
             created_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {idempotency} (\
             id VARCHAR(36) PRIMARY KEY,\
             ikey VARCHAR(128) NOT NULL UNIQUE,\
             endpoint VARCHAR(32) NOT NULL,\
             txn_id VARCHAR(36),\
             amount_cents BIGINT,\
             currency VARCHAR(3),\
             wallet_id VARCHAR(36),\
             balance_cents BIGINT,\
             created_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {favorites} (\
             id VARCHAR(36) PRIMARY KEY,\
             owner_wallet_id VARCHAR(36) NOT NULL,\
             favorite_wallet_id VARCHAR(36) NOT NULL,\
             alias VARCHAR(64),\
             created_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {requests} (\
             id VARCHAR(36) PRIMARY KEY,\
             from_wallet_id VARCHAR(36) NOT NULL,\
             to_wallet_id VARCHAR(36) NOT NULL,\
             amount_cents BIGINT NOT NULL,\
             currency VARCHAR(3) NOT NULL,\
             message VARCHAR(255),\
             status VARCHAR(16) NOT NULL,\
             created_at TEXT NOT NULL,\
             expires_at TEXT\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {aliases} (\
             id VARCHAR(36) PRIMARY KEY,\
             handle VARCHAR(32) NOT NULL UNIQUE,\
             display VARCHAR(32) NOT NULL,\
             user_id VARCHAR(36) NOT NULL,\
             wallet_id VARCHAR(36) NOT NULL,\
             status VARCHAR(16) NOT NULL DEFAULT 'pending',\
             code_hash VARCHAR(64),\
             code_expires_at TEXT,\
             created_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {roles} (\
             id VARCHAR(36) PRIMARY KEY,\
             account_id VARCHAR(64),\
             phone VARCHAR(32),\
             role VARCHAR(32) NOT NULL,\
             created_at TEXT NOT NULL\
             )"
        ),
        format!("CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON {users}(phone)"),
        format!("CREATE UNIQUE INDEX IF NOT EXISTS idx_users_account_id ON {users}(account_id)"),
        format!("CREATE UNIQUE INDEX IF NOT EXISTS idx_wallets_user_id ON {wallets}(user_id)"),
        format!("CREATE UNIQUE INDEX IF NOT EXISTS idx_idempotency_ikey ON {idempotency}(ikey)"),
        format!("CREATE INDEX IF NOT EXISTS idx_txns_created ON {txns}(created_at)"),
        format!("CREATE INDEX IF NOT EXISTS idx_txns_from_wallet ON {txns}(from_wallet_id)"),
        format!("CREATE INDEX IF NOT EXISTS idx_txns_to_wallet ON {txns}(to_wallet_id)"),
        format!("CREATE INDEX IF NOT EXISTS idx_favorites_owner ON {favorites}(owner_wallet_id)"),
        format!(
            "CREATE INDEX IF NOT EXISTS idx_requests_from_wallet ON {requests}(from_wallet_id)"
        ),
        format!("CREATE INDEX IF NOT EXISTS idx_requests_to_wallet ON {requests}(to_wallet_id)"),
        format!("CREATE UNIQUE INDEX IF NOT EXISTS idx_aliases_handle ON {aliases}(handle)"),
        format!("CREATE INDEX IF NOT EXISTS idx_roles_account_id ON {roles}(account_id)"),
        format!("CREATE INDEX IF NOT EXISTS idx_roles_phone ON {roles}(phone)"),
        format!("CREATE INDEX IF NOT EXISTS idx_roles_role ON {roles}(role)"),
    ];

    for ddl in ddls {
        let _ = sqlx::query(&ddl).execute(pool).await;
    }

    let _ = sqlx::query(&format!(
        "ALTER TABLE {txns} ADD COLUMN IF NOT EXISTS fee_cents BIGINT DEFAULT 0"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {requests} ADD COLUMN IF NOT EXISTS expires_at TEXT"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {idempotency} ADD COLUMN IF NOT EXISTS amount_cents BIGINT"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {idempotency} ADD COLUMN IF NOT EXISTS currency VARCHAR(3)"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {idempotency} ADD COLUMN IF NOT EXISTS wallet_id VARCHAR(36)"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {idempotency} ADD COLUMN IF NOT EXISTS balance_cents BIGINT"
    ))
    .execute(pool)
    .await;

    let _ = sqlx::query(&format!(
        "ALTER TABLE {users} ADD COLUMN IF NOT EXISTS account_id VARCHAR(64)"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {users} ALTER COLUMN phone DROP NOT NULL"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {roles} ADD COLUMN IF NOT EXISTS account_id VARCHAR(64)"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {roles} ALTER COLUMN phone DROP NOT NULL"
    ))
    .execute(pool)
    .await;

    Ok(())
}
