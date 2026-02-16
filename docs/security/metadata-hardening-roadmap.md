# Shamell Metadata-Hardening Roadmap

Status: Draft (implementation-oriented)  
Scope: Shamell Flutter client + BFF + chat_service + ops/pi deployment

## 1) Threat Model (one sentence)

Strong end-to-end content encryption alone is not enough against a strong observer: Shamell must minimize and blur who-talks-to-whom, when, and from where by default, while keeping end-to-end content encryption strict.

## 2) Scope Assumptions

- In scope: Shamell codebase, Shamell infrastructure, Shamell test/staging/prod configs.
- Out of scope: attacks against third-party systems.
- Adversaries:
  - A1: server operator / passive network observer.
  - A2: platform push provider metadata observer.
  - A3: multi-point/global traffic correlator (long-term target).

## 3) Target Architecture Blocks

### A. Identity without phone as primary identifier
- Keep device/account identity anchored on long-term public keys.
- Make phone optional for recovery/onboarding only (not for routing identity).
- Contact add flow: QR / invite link / short phrase (out-of-band).

### B. Anonymous transport path
- Move from direct client->chat-service visibility toward relay-based routing.
- Long-term: multi-hop onion-style forwarding with per-hop knowledge minimization.

### C. Dead-drop delivery (mailboxes)
- Route messages to mailbox tokens, not directly to stable user IDs.
- Sender writes ciphertext to mailbox; receiver polls mailbox via anonymized path.
- Rotate mailbox tokens periodically and on compromise events.

### D. Cover traffic
- Clients emit fixed-interval wake/poll patterns.
- Add indistinguishable dummy envelopes to reduce timing correlation.

### E. Content crypto (strict)
- Keep strict E2EE with forward secrecy and post-compromise recovery.
- Continue migration to standardized libsignal-style sessions (`v2_libsignal`) with no plaintext fallback.

### F. Privacy-preserving contact discovery (optional)
- Default: no address-book upload.
- Optional mode: PSI-style discovery where server only learns set intersection.

### G. Push model (wake-up only)
- Push payload must only wake the app.
- No sender/group/message identifiers in push provider payload.
- App fetches encrypted inbox after wake-up.

### H. Spam/DoS controls under anonymity
- Capability-based write permissions for first contact.
- Lightweight proof-of-work or token buckets per capability/mailbox.
- Replay-resistant envelope IDs + strict rate limits.

## 4) What is implemented now

- Group messaging can require `v2_libsignal` via `CHAT_PROTOCOL_REQUIRE_V2_FOR_GROUPS`.
- Per-device downgrade guard (`v2_only`) rejects legacy protocol fallback.
- Chat push payload is wake-up-only (`chat_wakeup`) with no sender/group/message metadata.
- Mailbox API is implemented behind rollout flag (`CHAT_MAILBOX_API_ENABLED=false`).

## 5) 1-3 Day Execution Plan (Top 5)

1. Default-enforce wake-up-only push everywhere (done in code; rollout via env + verification).
2. Add mailbox token schema + API skeleton (`issue`, `write`, `poll`, `rotate`) behind feature flag.
3. Introduce first-contact capability token check on message send.
4. Add fixed-interval polling mode in client (with jitter window) and telemetry for delivery latency.
5. Add CI guards: reject rich chat push payloads in prod/staging config tests.

## 6) Security Invariants (must hold)

- No plaintext group payload acceptance.
- No protocol downgrade for devices marked `v2_only`.
- No chat sender/group/message metadata in push provider payload in staging/prod.
- No implicit address-book upload unless explicit privacy mode is enabled.

## 7) Validation Checklist

- Unit tests: protocol enforcement, push payload minimization.
- Integration tests: key registration + bundle fetch + prekey lifecycle.
- E2E tests: push wake-up -> inbox pull -> decrypt flow.
- Runtime checks: alert if push payload includes forbidden metadata keys.
