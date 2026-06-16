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

    let cities = table_name(db_schema, "cities");
    let operators = table_name(db_schema, "bus_operators");
    let routes = table_name(db_schema, "routes");
    let trips = table_name(db_schema, "trips");
    let bookings = table_name(db_schema, "bookings");
    let tickets = table_name(db_schema, "tickets");
    let idempotency = table_name(db_schema, "idempotency");

    let ddls = [
        format!(
            "CREATE TABLE IF NOT EXISTS {cities} (\
             id VARCHAR(36) PRIMARY KEY,\
             name VARCHAR(120) NOT NULL,\
             country VARCHAR(64)\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {operators} (\
             id VARCHAR(36) PRIMARY KEY,\
             name VARCHAR(120) NOT NULL UNIQUE,\
             wallet_id VARCHAR(36),\
             is_online INTEGER NOT NULL DEFAULT 0\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {routes} (\
             id VARCHAR(36) PRIMARY KEY,\
             origin_city_id VARCHAR(36) NOT NULL,\
             dest_city_id VARCHAR(36) NOT NULL,\
             operator_id VARCHAR(36) NOT NULL,\
             bus_model VARCHAR(120),\
             features VARCHAR(1024)\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {trips} (\
             id VARCHAR(36) PRIMARY KEY,\
             route_id VARCHAR(36) NOT NULL,\
             depart_at TEXT NOT NULL,\
             arrive_at TEXT NOT NULL,\
             price_cents BIGINT NOT NULL,\
             currency VARCHAR(3) NOT NULL DEFAULT 'SYP',\
             seats_total INTEGER NOT NULL DEFAULT 40,\
             seats_available INTEGER NOT NULL DEFAULT 40,\
             status VARCHAR(16) NOT NULL DEFAULT 'draft'\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {bookings} (\
             id VARCHAR(36) PRIMARY KEY,\
             trip_id VARCHAR(36) NOT NULL,\
             price_cents BIGINT,\
             customer_phone VARCHAR(32),\
             wallet_id VARCHAR(36),\
             seats INTEGER NOT NULL DEFAULT 1,\
             status VARCHAR(16) NOT NULL DEFAULT 'pending',\
             payments_txn_id VARCHAR(64),\
             created_at TEXT\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {tickets} (\
             id VARCHAR(36) PRIMARY KEY,\
             booking_id VARCHAR(36) NOT NULL,\
             trip_id VARCHAR(36) NOT NULL,\
             seat_no INTEGER,\
             status VARCHAR(16) NOT NULL DEFAULT 'issued',\
             issued_at TEXT,\
             boarded_at TEXT\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {idempotency} (\
             key VARCHAR(120) PRIMARY KEY,\
             trip_id VARCHAR(36),\
             wallet_id VARCHAR(36),\
             seats INTEGER,\
             seat_numbers_hash VARCHAR(128),\
             booking_id VARCHAR(36),\
             created_at TEXT\
             )"
        ),
        format!("CREATE INDEX IF NOT EXISTS idx_cities_name ON {cities}(name)"),
        format!("CREATE INDEX IF NOT EXISTS idx_ops_name ON {operators}(name)"),
        format!("CREATE INDEX IF NOT EXISTS idx_trips_depart_at ON {trips}(depart_at)"),
        format!("CREATE INDEX IF NOT EXISTS idx_bookings_created_at ON {bookings}(created_at)"),
        format!("CREATE INDEX IF NOT EXISTS idx_tickets_trip ON {tickets}(trip_id)"),
    ];

    for ddl in ddls {
        let _ = sqlx::query(&ddl).execute(pool).await;
    }

    let _ = sqlx::query(&format!(
        "ALTER TABLE {trips} ADD COLUMN IF NOT EXISTS status VARCHAR(16) DEFAULT 'draft'"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "UPDATE {trips} SET status='draft' WHERE status IS NULL"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {routes} ADD COLUMN IF NOT EXISTS bus_model VARCHAR(120)"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {routes} ADD COLUMN IF NOT EXISTS features VARCHAR(1024)"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {bookings} ADD COLUMN IF NOT EXISTS trip_id VARCHAR(36)"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {tickets} ADD COLUMN IF NOT EXISTS trip_id VARCHAR(36)"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {operators} ADD COLUMN IF NOT EXISTS is_online INTEGER DEFAULT 0"
    ))
    .execute(pool)
    .await;

    Ok(())
}
