use shamell_chat_service::{config::Config, db};
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    let cfg = match Config::from_env() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };

    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .json()
        .init();

    let pool = match db::connect(&cfg.db_url).await {
        Ok(p) => p,
        Err(e) => {
            tracing::error!(error = %e, "db connect failed");
            std::process::exit(2);
        }
    };

    if let Err(e) = db::apply_versioned_schema_migrations(&pool, &cfg.db_schema).await {
        tracing::error!(error = %e, "chat versioned SQL migration failed");
        std::process::exit(2);
    }

    if let Err(e) = db::ensure_schema(&pool, &cfg.db_schema).await {
        tracing::error!(error = %e, "chat legacy schema convergence failed");
        std::process::exit(2);
    }

    tracing::info!(db_schema = ?cfg.db_schema, "chat schema migration completed");
}
