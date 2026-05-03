# payments_service — WIP / not buildable

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
pub mod state;
```

`src/db.rs` and `src/handlers.rs` were never materialised in the V2
rewrite, but `src/main.rs` and migrations under `migrations/` already
assume their existence.

The implementations of these symbols still live elsewhere (origin/main
hosts the Python monolith equivalents under `apps/payments/`).

## Path forward

Two options, in priority order:

1. Port the relevant `apps/payments/` endpoints from origin/main into
   this crate (transfer, balance, topup, voucher) handler-by-handler
   with sqlx, against the migrations that already live in this crate.
2. Stand up a thin `db.rs` / `handlers.rs` skeleton that returns 501
   Not Implemented for everything except `/healthz`, to unblock the
   workspace build.

Until either is done this crate stays excluded.
