# Threema-Style Chat – Minimal Vertical (Flutter)

Stack choice: **Flutter + Dart + libsodium (pinenacl) + WebRTC later**. We start with a thin vertical that is shippable and matches Threema’s core behaviours: on-device identity, QR verification, end-to-end encrypted 1:1 messaging, and push-driven delivery.

## Goals for the first vertical
- Onboarding creates a Threema-like ID and X25519 keypair locally; private key never leaves device.
- Show/share own ID + fingerprint as QR; scan peer QR to add/verify contact.
- 1:1 chat with text + images (encrypted), delivery/read markers, live updates (WS/SSE) and periodic pull.
- Push wakeups via FCM to nudge inbox refresh (payload stays opaque).
- Local persistence of identity, contacts, threads, and messages (offline read + pending send).
- Encrypted image attachments (small inline blobs) inside the message payload.

## Crypto model
- Curve25519 (NaCl box) with random 24-byte nonce per message. `pinenacl` is already in the client; backend stores ciphertext/nonce only.
- Fingerprint: `hex(sha256(pubkey))[0:16]` (matches current implementation). Used for QR and verification.
- Attachments: encrypt bytes with the same box + nonce; base64 payload stored in message record (short-term). Longer term move to object storage with encrypted blobs.
- Future: per-conversation session keys / double ratchet; for this vertical we keep the static keypair + per-message nonce.

## Backend surface (apps/chat)
Existing endpoints are sufficient for the thin slice: device register, device lookup, send, inbox, read, WS inbox. Needed additions for push:
- `POST /chat/devices/{id}/push_token` (FCM token, platform, expires_at).
- Optional: server-side fanout to FCM on message insert (notify recipient to pull).
Until that exists, client will use WS/poll; push token can be staged but no-op.

## Client architecture (Flutter)
- **Identity store**: generate/store `deviceId`, `pubKey`, `privKey`, `fingerprint`, `displayName`, `verifiedPeers` in secure storage (prefer `flutter_secure_storage`; fallback to shared prefs if unavailable).
- **Contact store**: minimal SQLite/Isar (to add) for contacts + threads. For the first drop we can keep an in-memory list hydrated from storage.
- **Networking**: typed service wrapping `/chat` endpoints; WS inbox listener with backoff; HTTP pull fallback.
- **Messaging model**: `ChatMessage { id, senderId, recipientId, nonceB64, boxB64, createdAt, deliveredAt?, readAt?, media? }` with optional encrypted image attachment embedded in the payload JSON (`text`, `attachment_b64`, `attachment_mime`).
- **UI flows**:
  - Onboarding: name (optional), generate ID/keypair, show fingerprint + QR, allow export of safety key.
  - Contact add/verify: scan QR containing `{id, pubKeyB64, fp}`; show trust levels (unknown/verified) with side-by-side fingerprints and manual confirm.
  - Chats list: conversations sorted by latest message, unread badge, last message preview.
  - Thread: bubble UI, text input, image attach, sending state, read/delivered ticks, pull-to-refresh.
  - Settings: regenerate QR, view fingerprint, toggle app-lock (local_auth) and backup/export (later).
  - Disappearing messages: per-thread toggle, client-side expiration countdown and optional server-side expire time (purge applied on inbox/stream; full background sweep still to be added).
- **Push glue**: request FCM permission, obtain token, call new `/chat/devices/{id}/push_token`; show local notification on foreground message (with optional previews the user can toggle).

## Thin vertical scope (what we will build now)
- Identity onboarding + QR share/scan.
- Contact verification stored locally.
- 1:1 text + image send/receive using existing `/chat` API.
- WS listener + manual pull; optimistic send queue.
- FCM registration on client side; server endpoint `/chat/devices/{id}/push_token` + fanout (legacy FCM key) to wake the recipient to pull. Notifications can hide content unless the user enables previews.

## Notable constraints / deltas vs Threema
- No multi-device sync yet; single-device identity only.
- No voice/video calls in the first slice; plan to add via WebRTC after messaging solidifies.
- Disappearing messages: client-enforced plus server-side expire timestamps (purged on inbox/stream and via background loop); ciphertext may linger briefly depending on purge interval. Hidden chats implemented locally (biometric gate) but not server-hidden.
- Blocked contacts: enforced server-side (send fails 403 if recipient blocks sender; inbox/WS omit blocked peers) plus client-side mute/drop.
- Sealed sender + ratchet (in progress): sealed-view inbox/WS, hints + key ids, sender DH pub in payload, client-side ratchet (root/send/recv chains, skipped-key cache, secure storage). Safety number + reset UI and key-change warnings added; interop/E2E tests still needed for ratchet window/replay protection.
- Safety number / session reset: show combined fingerprint hash, allow session reset if mismatch or key change detected (client-side). DH ratchet in progress with skipped-key cache and sealed inbox; ensure DB migrations apply for ratchet fields.
- Identity backup/restore: passphrase-encrypted export (SecretBox + PBKDF2) via in-app backup text.
- Backups/export: deferred; we can add passphrase-protected key export later.
