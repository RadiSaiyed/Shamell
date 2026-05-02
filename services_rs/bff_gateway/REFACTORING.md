# bff_gateway — outstanding refactoring debt

This crate is the active workspace member, but its source-file
sizes are well outside healthy Rust norms. The largest two files
account for ~85% of the crate's LoC:

| File | LoC | Functions | Structs / impls |
|------|-----|-----------|-----------------|
| `src/handlers.rs` | **74,794** | 1,410 | 172 |
| `src/auth.rs` | **33,049** | (many) | (many) |
| `src/main.rs` | 6,830 | | |
| `src/coach_catalog.rs` | 5,090 | | |
| `src/config.rs` | 2,960 | | |
| `src/coach_gtfs.rs` | 1,642 | | |
| `src/models.rs` | 706 | | |
| `src/state.rs` | 585 | | |
| `src/authz.rs` | 258 | | |

## Why this matters

- `cargo build`, `cargo check` and `rust-analyzer` all reanalyse a
  single 74k-line file on every change in that file. Compile times
  and IDE responsiveness degrade nonlinearly.
- Code review on PRs touching `handlers.rs` is impractical;
  reviewers cannot hold the surface in working memory.
- `cargo test` runs all tests in one compilation unit, blocking the
  ability to run a feature's tests in isolation.

## Suggested decomposition (no behaviour change)

1. **Top-level domain split for `handlers.rs`**: introduce
   `src/handlers/` directory and move handler groups into siblings
   such as `auth.rs`, `chat.rs`, `payments.rs`, `coach.rs`,
   `mailbox.rs`, `presence.rs`, `device.rs`. Keep
   `src/handlers/mod.rs` as the re-export hub.
2. **Same for `auth.rs`**: split into `auth/session.rs`,
   `auth/device_login.rs`, `auth/workforce.rs`,
   `auth/internal_identity.rs`, `auth/jwks.rs`.
3. Move test modules (currently inline `#[cfg(test)] mod tests`) to
   `tests/` integration files where they don't gate compilation of
   the primary build.
4. Keep `lib.rs` as the public re-export surface; do not flatten
   pub APIs.

## Why we did **not** do it in the cleanup pass

The decomposition is large, behaviour-preserving but mechanical
work that needs `cargo build` + `cargo test` running locally to
verify every move. The cleanup pass that produced this file did
not have a Rust toolchain installed on the host; running the
refactor without compiler verification is too risky for a service
that authenticates the entire mobile fleet.

The split should happen in a dedicated PR series, one domain group
at a time, each PR bounded to "move handlers, no behaviour change",
gated by `cargo test --workspace` going green.

## Other follow-ups in this crate

- `src/auth.rs:21466+` test mod (`#[cfg(test)] mod tests`) holds
  the inline test PEM constants. Once `auth.rs` is split, these
  should move to `tests/` integration files.
- Re-evaluate the 167+ `.clone()` call sites flagged in the
  initial audit once the file is small enough to grep
  per-handler.
