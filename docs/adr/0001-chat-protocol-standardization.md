# ADR 0001: Standardize Shamell Chat Protocol (Signal-Style) and Remove Bespoke-Crypto Risk

Status: Proposed (2026-02-15)  
Owners: AppSec + Chat Platform  
Scope: Shamell Flutter client, BFF, chat service, key APIs, CI tests

## Threat Model (One Sentence)
Assume a malicious network and untrusted server/router that can observe or tamper with traffic: Shamell must preserve message confidentiality/integrity end-to-end, fail closed on crypto preconditions, and prevent protocol downgrades during migration.

## Context
Shamell currently has protocol versioning and migration guardrails (e.g. `v2_only`, group-chat v2 requirement), but still carries bespoke/hand-rolled crypto logic on the client side and lacks a standardized, externally-reviewed protocol stack for sessions and groups.

This leaves a high residual risk of:
- protocol-design flaws / edge cases
- downgrade paths or accidental fallback
- interoperability drift between clients
- missing formal review and test vectors

Related doc (more detailed): `docs/security/chat-protocol-libsignal-migration-rfc.md`.

## Decision
1. Shamell will converge on a standardized, Signal-style protocol stack for 1:1 sessions and group messaging.
2. Migration is gated by explicit protocol versioning and strict downgrade prevention (no silent fallback).
3. Phase 0 introduces a protocol abstraction boundary and deterministic regression tests ("golden vectors") without changing production message crypto yet.

## Licensing Constraint (Hard Gate)
"Official" libsignal implementations are frequently GPL/AGPL. Until Shamell's overall licensing is explicitly decided, we must **not** introduce GPL/AGPL dependencies into shipped client/server artifacts.

Phase 0 therefore:
- avoids GPL/AGPL dependencies in production crates
- allows MIT/BSD/Apache dependencies
- permits using a permissively-licensed reference implementation in tests only (to seed vectors and harnesses)

## Consequences
### Positive
- Clear migration path away from bespoke crypto.
- Ability to add protocol-level regression tests before touching message paths.
- Safer rollouts via versioning, "no downgrade", and interop fixtures.

### Tradeoffs / Risks
- Until Phase 1+ completes, bespoke crypto remains the dominant risk.
- Test-only reference backends may diverge from "official" semantics; vectors must be treated as migration tools, not proof of formal correctness.

## Implementation Plan (Phased)
### Phase 0 (1-3 days)
- Add `crates_rs/shamell_signal` with:
  - stable API surface to host future engine integrations
  - deterministic primitives needed for user-verifiable key-change UX (safety numbers)
  - golden-vector regression tests

Exit criteria:
- `cargo test -p shamell_signal` green
- documented constraints + migration gates

### Phase 1 (next)
- Choose a license-compatible, audited Signal protocol implementation (or relicense Shamell if needed).
- Implement a real backend behind the `SignalEngine` interface.
- Add protocol-level golden vectors + interop tests (session init, message encrypt/decrypt, group sender-key flows).

### Phase 2+
- Client rollout (feature flags), safety-number UX, key-change detection, and hard disable legacy paths by policy.

## Security Regression Tests (Must Have)
- "No downgrade" tests for `v2_only` devices and group v2 requirement (server + client).
- Key-change detection tests (identity key rotation triggers warnings / blocks).
- Golden vectors for protocol primitives and session flows.

