use shamell_bff_gateway::auth;
use sqlx::PgPool;
use std::env;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .json()
        .init();

    let db_url = env::var("DB_URL").unwrap_or_default();
    let db_url = db_url.trim().to_string();
    if db_url.is_empty() {
        eprintln!("DB_URL must be configured for BFF auth schema migration");
        std::process::exit(2);
    }

    let pool = match PgPool::connect(&db_url).await {
        Ok(pool) => pool,
        Err(e) => {
            tracing::error!(error = %e, "auth postgres connect failed");
            std::process::exit(2);
        }
    };

    if let Err(e) = auth::apply_versioned_auth_schema_migrations(&pool).await {
        tracing::error!(error = %e, "bff auth versioned SQL migration failed");
        std::process::exit(2);
    }

    if let Err(e) = auth::ensure_auth_schema(&pool).await {
        tracing::error!(error = %e, "bff auth legacy schema convergence failed");
        std::process::exit(2);
    }

    tracing::info!("bff auth schema migration completed");
}
