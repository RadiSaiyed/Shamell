#!/usr/bin/env bash
set -euo pipefail

# BFF caller-identifier trust guard.
#
# Background: the BFF receives request bodies that name the caller's own
# wallet / device / account. If a handler blindly forwards that body to a
# downstream service, an attacker who knows another user's wallet_id can
# perform actions attributed to that wallet. We caught this exact bug in
# the hotels mini-app (May 2026) and fixed it via require_wallet_ownership.
#
# This guard makes the bug-class structurally hard to repeat: every BFF
# request-body struct that exposes a caller-identifier field MUST be on
# the allowlist below. Adding a new struct is intentional friction — the
# PR author has to audit the gating path and explicitly opt in.
#
# Caller-identifier fields tracked:
#   wallet_id, from_wallet_id, owner_wallet_id, to_wallet_id,
#   creator_wallet_id, sender_id, account_id, creator_account_id,
#   device_id (the chat / push surface's caller id), operator_account_id,
#   inviter_id, actor_id, moderator_device_id

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ALLOWLIST="$ROOT/scripts/bff_caller_identifier_trust_allowlist.txt"
SOURCES=(
  services_rs/bff_gateway/src/models.rs
  services_rs/bff_gateway/src/handlers.rs
  services_rs/bff_gateway/src/hotels_proxy.rs
  services_rs/bff_gateway/src/auth.rs
)

if [[ ! -f "$ALLOWLIST" ]]; then
  echo "[FAIL] allowlist file missing: $ALLOWLIST" >&2
  exit 1
fi

for src in "${SOURCES[@]}"; do
  if [[ ! -f "$src" ]]; then
    echo "[FAIL] expected BFF source file missing: $src" >&2
    exit 1
  fi
done

# Extract struct names that:
#   (a) carry #[derive(...Deserialize...)] (so they're a request-body shape),
#   (b) contain at least one pub field that names a caller identifier.
# Walks the file with a small state machine: tracks the most recent derive,
# remembers the struct name on `pub struct NAME`, scans the body until the
# closing `}` at column 0, then emits the name if a flagged field appeared.
FOUND_RAW="$(
  awk '
    BEGIN { is_deser = 0; struct_name = ""; has_caller_field = 0 }

    # Track derive(...) attributes. A single derive may span lines, but in
    # this codebase every Deserialize derive sits on a single line — keep
    # it simple. Reset the flag if we hit a non-attribute, non-struct line.
    /^#\[derive\(.*Deserialize.*\)\]/ { is_deser = 1; next }

    # serde attribute lines may appear between derive and struct; pass through.
    /^#\[serde/ { next }

    # Struct declaration. If derive(Deserialize) is pending, capture the name.
    /^pub struct [A-Za-z_][A-Za-z0-9_]*/ {
      if (is_deser) {
        name = $0
        sub(/^pub struct /, "", name)
        sub(/[ <{].*$/, "", name)
        struct_name = name
      } else {
        struct_name = ""
      }
      is_deser = 0
      has_caller_field = 0
      next
    }

    # End of a top-level struct body (closing brace at column 0).
    /^\}/ {
      if (struct_name != "" && has_caller_field) print struct_name
      struct_name = ""
      has_caller_field = 0
      is_deser = 0
      next
    }

    # Reset derive flag on any other top-level item so it does not "stick"
    # to the next struct.
    /^pub / || /^fn / || /^impl / || /^async fn / {
      is_deser = 0
    }

    # Inside a Deserialize struct: flag caller-identifier fields. Match both
    # `pub field:` (request body) and `field:` (handlers.rs internal request
    # structs that are still Deserialized from JSON).
    struct_name != "" && /^[[:space:]]*(pub[[:space:]]+)?(wallet_id|from_wallet_id|owner_wallet_id|to_wallet_id|target_wallet_id|source_wallet_id|favorite_wallet_id|creator_wallet_id|sender_id|account_id|creator_account_id|operator_account_id|device_id|client_device_id|moderator_device_id|inviter_id|actor_id):/ {
      has_caller_field = 1
    }
  ' "${SOURCES[@]}" | LC_ALL=C sort -u
)"

ALLOWED_RAW="$(
  grep -v -E '^[[:space:]]*(#|$)' "$ALLOWLIST" | LC_ALL=C sort -u
)"

# Diff: anything in $FOUND not in $ALLOWED is a new unaudited struct.
NEW="$(LC_ALL=C comm -23 <(printf '%s\n' "$FOUND_RAW") <(printf '%s\n' "$ALLOWED_RAW") || true)"

# Anything in $ALLOWED not in $FOUND is stale — the struct was renamed or
# removed. We warn but don't fail, since deletion is safe.
STALE="$(LC_ALL=C comm -13 <(printf '%s\n' "$FOUND_RAW") <(printf '%s\n' "$ALLOWED_RAW") || true)"

errors=0

if [[ -n "$NEW" ]]; then
  echo "[FAIL] BFF request-body struct(s) carry a caller-identifier field" >&2
  echo "       but are not in the gating allowlist:" >&2
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    echo "         $name" >&2
  done <<< "$NEW"
  echo "" >&2
  echo "  Each such struct MUST be wired into one of the canonical" >&2
  echo "  ownership gates BEFORE its handler forwards the body upstream:" >&2
  echo "    * Payments:  canonical_payments_*_body in handlers.rs" >&2
  echo "    * Chat:      require_chat_guardrails_if_configured (proxy layer)" >&2
  echo "    * Hotels:    require_wallet_ownership in hotels_proxy.rs" >&2
  echo "    * Admin:     authz::require_admin middleware (role-based)" >&2
  echo "" >&2
  echo "  After gating, add the struct name to:" >&2
  echo "    $ALLOWLIST" >&2
  echo "  with a one-line note saying which gate it sits behind." >&2
  errors=1
fi

if [[ -n "$STALE" ]]; then
  echo "[WARN] allowlist entries no longer match any BFF source struct:" >&2
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    echo "         $name" >&2
  done <<< "$STALE"
  echo "       Remove these from $ALLOWLIST." >&2
fi

if (( errors != 0 )); then
  exit 1
fi

echo "[OK]   BFF caller-identifier trust guard passed."
