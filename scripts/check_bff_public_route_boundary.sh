#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/services_rs/bff_gateway/src/main.rs"

fail() {
  echo "BFF public-route boundary check failed: $*" >&2
  exit 1
}

[[ -f "$FILE" ]] || fail "missing file: $FILE"

public_block="$(
  awk '
    /let public_auth = Router::new\(\)/ { capture=1 }
    capture { print }
    /let public_auth = if cfg\.auth_device_login_web_enabled \{/ { exit }
  ' "$FILE"
)"

session_block="$(
  awk '
    /let session_routes = Router::new\(\)/ { capture=1 }
    capture { print }
    /let authed = Router::new\(\)/ { exit }
  ' "$FILE"
)"

authed_block="$(
  awk '
    /let authed = Router::new\(\)/ { capture=1 }
    capture { print }
    /let public_auth = Router::new\(\)/ { exit }
  ' "$FILE"
)"

public_auth_cors_block="$(
  awk '
    /let public_auth = public_auth\.layer\(cors_layer_for_headers\(/ { capture=1 }
    capture { print }
    /let csrf_state = CsrfState \{/ { exit }
  ' "$FILE"
)"

[[ -n "$public_block" ]] || fail "unable to extract public_auth router block"
[[ -n "$session_block" ]] || fail "unable to extract session_routes router block"
[[ -n "$authed_block" ]] || fail "unable to extract authed router block"
[[ -n "$public_auth_cors_block" ]] || fail "unable to extract public_auth CORS layer block"

while IFS= read -r forbidden; do
  [[ -n "$forbidden" ]] || continue
  if grep -Fq -- "$forbidden" <<<"$public_block"; then
    fail "forbidden authenticated route leaked into public_auth: $forbidden"
  fi
done <<'EOF'
"/auth/devices/register"
"/auth/devices"
"/official_accounts"
"/official_accounts/notifications"
"/official_accounts/:account_id/auto_replies"
"/official_accounts/:account_id/follow"
"/official_accounts/:account_id/unfollow"
"/official_accounts/:account_id/notification_mode"
"/admin/official_accounts/:account_id/auto_replies"
"/admin/official_accounts/:account_id"
"/admin/official_accounts/:account_id/moments_stats"
"/admin/official_accounts/:account_id/owners"
"/admin/official_auto_replies/:rule_id"
"/admin/official_feeds"
"/admin/official_accounts/:account_id/service_inbox"
"/me/roles"
"/me/home_snapshot"
"/me/geo/reverse"
"/me/geo/search"
"/me/rides/search"
"/me/rides/bootstrap"
"/me/rides/route"
"/me/rides/traffic"
"/me/official_template_messages"
EOF

while IFS= read -r required; do
  [[ -n "$required" ]] || continue
  if ! grep -Fq -- "$required" <<<"$session_block"; then
    fail "required authenticated route missing from session_routes: $required"
  fi
done <<'EOF'
"/auth/devices/register"
"/auth/devices"
"/official_accounts"
"/official_accounts/:account_id/follow"
"/admin/official_accounts/:account_id/owners"
"/me/home_snapshot"
"/me/geo/search"
"/me/rides/bootstrap"
EOF

if ! grep -Fq 'bff_public_cors_allowed_headers()' <<<"$public_auth_cors_block"; then
  fail "public_auth must keep the minimal public CORS allowlist"
fi

if ! grep -Fq '.merge(session_routes.layer(cors_layer_for_headers(' <<<"$authed_block"; then
  fail "authed router no longer merges session_routes through cors_layer_for_headers"
fi

if ! grep -Fq 'bff_session_cors_allowed_headers()' <<<"$authed_block"; then
  fail "session_routes must use bff_session_cors_allowed_headers()"
fi

echo "BFF public/session route boundary looks correct"
