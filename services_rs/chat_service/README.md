# chat_service — WIP / not buildable

This crate is **intentionally excluded** from the workspace
(`Cargo.toml > workspace.exclude`) because it does not compile in
its current form.

## Why

`src/lib.rs` declares the module graph:

```rust
pub mod config;
pub mod db;        // <-- missing
pub mod error;
pub mod handlers;  // <-- missing
pub mod models;
pub mod push_token_crypto;
pub mod state;
```

`src/db.rs` and `src/handlers.rs` were never materialised in the V2
rewrite, but `src/main.rs` already calls into them:

- `db::connect`, `db::apply_versioned_schema_migrations`,
  `db::ensure_schema`, `db::assert_schema_ready`
- `handlers::register`, `handlers::get_device`,
  `handlers::direct_peer_guard`, `handlers::bootstrap_keys`,
  `handlers::purge_expired`, `handlers::cleanup_chat_rate_limits`, …

The implementations of these symbols still live elsewhere (origin/main
hosts the Python monolith equivalents under `apps/chat/`).

## Path forward

Two options, in priority order:

1. Port the relevant `apps/chat/` endpoints from origin/main into this
   crate (handler-by-handler, with sqlx queries, behind feature flags).
2. Stand up a thin `db.rs` / `handlers.rs` skeleton that returns 501
   Not Implemented for everything except `/healthz`, just to unblock
   the workspace build.

Until either is done this crate stays excluded.
