# Chat Protocol Migration RFC: Shamell -> libsignal

Status: Draft (proposed)  
Scope: Shamell Flutter client + chat service + BFF integration  
Owner: AppSec + Chat Platform

See also: `docs/adr/0001-chat-protocol-standardization.md`.

Implementation snapshot (server):
- Phase 0 foundations are implemented (`protocol_version` on messages/groups + rollout flags).
- Phase 1 server key API contract is implemented:
  - `POST /keys/register`
  - `POST /keys/prekeys/upload`
  - `GET /keys/bundle/:device_id`
- Per-device downgrade guard (`v2_only`) is enforced for message sends.
- Flutter client is wired for staged rollout via compile-time flags:
  - `CHAT_PROTOCOL_V2_SEND`
  - `ENABLE_LIBSIGNAL_KEY_API`
  - `CHAT_PROTOCOL_V2_ONLY`
  - active outbound chat sessions bootstrap via `GET /keys/bundle/:device_id` before first ratchet use

Important note (security): `v2_libsignal` is currently an **experimental** protocol label and rollout
scaffold. Until a real libsignal-backed engine is integrated and externally audited, Shamell still
has residual risk from custom/transition crypto paths and edge cases.

## 1. Decision Summary

Shamell will migrate from the current custom chat cryptography implementation to
a libsignal-based protocol stack with standard session semantics.

Primary security decisions:
- Use libsignal protocol primitives instead of custom KDF/ratchet code.
- Keep server as ciphertext router only; never accept plaintext group messages.
- Roll out with explicit protocol versioning and dual-stack compatibility until
  all active clients are upgraded.
- Fail closed on cryptographic preconditions (no silent fallback to plaintext).

## 2. Why this RFC exists

Current baseline has defensive improvements, but still relies on custom crypto
paths in the client. Migration is required to reduce protocol-design risk and
align with industry-standard, externally scrutinized primitives.

Current custom-crypto evidence in repo:
- Custom ratchet/KDF logic: `clients/shamell_flutter/lib/core/chat/shamell_chat_page.dart`
- Client chat crypto service: `clients/shamell_flutter/lib/core/chat/chat_service.dart`
- Chat transport/storage endpoints: `services_rs/chat_service/src/handlers.rs`

## 3. Goals

- Replace custom message-session crypto with libsignal-backed sessions.
- Keep 1:1 and group chat end-to-end encrypted with no plaintext fallback.
- Introduce explicit protocol versioning (`v1_legacy`, `v2_libsignal`).
- Provide reversible rollout controls and measurable exit criteria.

## 4. Non-goals

- No cross-platform rewrite of the entire chat UI in this RFC.
- No change to auth/session model outside chat protocol-specific needs.
- No guarantee of zero-breaking-change for obsolete clients.

## 5. Threat Model Delta

Assets:
- Message confidentiality/integrity.
- Long-term identity keys and session state.
- Group sender-key material.

Main trust boundaries:
- Client secure key store boundary.
- Network/API boundary between client and chat service.
- Chat service persistence boundary (ciphertext + metadata only).

Threats addressed:
- Design flaws from homegrown cryptographic constructions.
- Downgrade attempts to legacy protocol during migration.
- Accidental plaintext submission/acceptance in group flows.

## 6. Target Architecture (v2_libsignal)

Client:
- libsignal identity key pair per device.
- Signed prekey + one-time prekeys managed by client and published to server.
- libsignal session store for peer sessions.
- Group sender-key flow backed by libsignal-compatible envelopes.

Server:
- Key-bundle directory and prekey consumption APIs.
- Strict ciphertext envelope validation for all chat message endpoints.
- No server-side plaintext parsing of user message content.
- Protocol version enforcement and downgrade protection policy.

## 7. API and Data Model Changes

### 7.1 Protocol Versioning

Add explicit protocol version to chat message envelopes:
- `protocol_version`: `v1_legacy | v2_libsignal`

Rules:
- New clients send only `v2_libsignal`.
- Server supports both during migration window.
- Server rejects any downgrade for users/devices marked `v2_only`.

### 7.2 New/updated endpoints (conceptual)

- `POST /chat/keys/register`  
  register identity key + signed prekey + signature
- `POST /chat/keys/prekeys/upload`  
  upload one-time prekey batch
- `GET /chat/keys/bundle/:device_id`  
  fetch peer key bundle
- `POST /chat/messages/send`  
  accept versioned ciphertext envelope only
- `POST /chat/groups/:gid/messages/send`  
  accept versioned ciphertext envelope only

### 7.3 Storage changes (conceptual)

Add tables:
- `chat_identity_keys`
- `chat_signed_prekeys`
- `chat_one_time_prekeys`
- `chat_device_protocol_state`

Adjust existing message records:
- add `protocol_version` column
- preserve ciphertext fields only
- keep metadata minimum required for delivery/order

## 8. Rollout Plan

## Phase 0: Foundations (week 0-1)
- Add protocol version fields and server validation plumbing.
- Add feature flags:
  - `CHAT_PROTOCOL_V2_ENABLED`
  - `CHAT_PROTOCOL_V1_WRITE_ENABLED`
  - `CHAT_PROTOCOL_V1_READ_ENABLED`
  - `CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS`
- Add telemetry counters for v1/v2 send/read paths.

Exit criteria:
- v2 schema + flags deployed in dev/staging.
- No plaintext acceptance path in group send endpoints.

## Phase 1: Dual-stack introduction (week 1-2)
- Integrate libsignal in Flutter client behind runtime gate.
- Keep read compatibility with legacy messages.
- New sessions can negotiate v2; existing sessions remain readable.

Exit criteria:
- Staging canary clients exchange v2 1:1 and group messages.
- No downgrade without explicit allow flag.

## Phase 2: Canary and ramp (week 2-3)
- Enable v2 for internal users and 5-10% canary.
- Monitor:
  - send failures by protocol version
  - prekey depletion
  - session-init errors
  - decrypt failures

Exit criteria:
- Stable error rate and no critical decrypt regressions.

## Phase 3: Default v2 (week 3-4)
- Default all new installs/sessions to v2.
- Mark active upgraded devices as `v2_only`.
- Keep temporary v1 read fallback for bounded window.

Exit criteria:
- >=95% active devices on v2.
- No unresolved Sev-1/Sev-2 crypto incidents.

## Phase 4: Sunset v1 (target date set by metrics)
- Disable v1 writes globally.
- Disable v1 reads after migration grace period.
- Remove legacy protocol code paths and flags.

Exit criteria:
- 100% active devices v2.
- legacy endpoints/branches removed from codebase.

## 9. Security Controls During Migration

- Fail-closed on missing key material for v2 sends.
- Enforce strict version policy per device (`v2_only` guard).
- Keep structured security logs for:
  - protocol downgrade attempts
  - key-bundle fetch anomalies
  - repeated decrypt failures
- Keep chat push wake-up only so provider payloads do not carry
  sender/group/message identifiers.
- Keep CI checks blocking plaintext group-send paths.

## 10. Test Strategy

Required automated tests:
- Unit:
  - envelope validation by protocol version
  - downgrade rejection for `v2_only`
- Integration:
  - key registration, prekey upload/consume lifecycle
  - v2 1:1 and group message delivery
- E2E:
  - mixed fleet (v1+v2) compatibility in migration window
  - canary rollback behavior when `CHAT_PROTOCOL_V2_ENABLED=false`
- Security regression:
  - no plaintext group message acceptance
  - no unsafe local key fallback defaults

## 11. Operational Runbook Changes

- Add prekey capacity alerts (low prekey inventory).
- Add dashboard slices for protocol mix and decrypt error rates.
- Add emergency rollback playbook:
  - disable v2 writes quickly
  - keep v2 reads enabled for already-delivered messages

## 12. Cutover Gates (must-pass)

Before enabling `v2_only` for all users:
- All mandatory tests green in CI.
- Canary metrics stable over agreed observation window.
- Incident runbook updated with v2-specific triage steps.
- Security sign-off from AppSec owner.

## 13. Backward Compatibility Policy

- Legacy support is temporary and metrics-driven.
- Old clients may break after sunset threshold is reached.
- Product/ops must communicate deprecation timeline before v1 removal.

## 14. Immediate Next Implementation Tasks

1. Add chat protocol version field and DB migration scaffolding.
2. Implement key-bundle API contract in chat service.
3. Integrate libsignal client store abstraction in Flutter app.
4. Add downgrade-protection checks and telemetry.
5. Ship staged canary rollout configuration for staging.
