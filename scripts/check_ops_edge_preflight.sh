#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPS_SCRIPT="${ROOT}/scripts/ops.sh"
SNIPPET_PATH="${ROOT}/ops/hetzner/nginx/snippets/shamell_cloudflare_realip.conf"

tmpbin="$(mktemp -d)"
valid_env="$(mktemp)"
invalid_env="$(mktemp)"
stale_snippet="$(mktemp)"
ok_out="$(mktemp)"
ok_err="$(mktemp)"
bad_out="$(mktemp)"
bad_err="$(mktemp)"

cleanup() {
  rm -rf "$tmpbin" "$valid_env" "$invalid_env" "$stale_snippet" "$ok_out" "$ok_err" "$bad_out" "$bad_err"
}
trap cleanup EXIT

cat >"${tmpbin}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "${tmpbin}/ssh"

cat >"${tmpbin}/scp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "${tmpbin}/scp"

cat >"$valid_env" <<'EOF'
POSTGRES_USER=shamell
POSTGRES_PASSWORD=secret123
DB_URL=postgres://shamell:secret123@localhost/shamell_core
CHAT_DB_URL=postgres://shamell:secret123@localhost/shamell_chat
PAYMENTS_DB_URL=postgres://shamell:secret123@localhost/shamell_payments
INTERNAL_API_SECRET=internal-secret-123
BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS=pubkey1
BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS=control-automation,iam-sync
BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS=control-automation=pubkey4,iam-sync=pubkey5
BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_MAX_SKEW_SECS=30
BFF_ACCESS_ASSIGNMENT_REQUIRE_INTERNAL_IDENTITY_V2=true
BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK=false
BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64=seed123
ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID=control-automation
ACCESS_ASSIGNMENT_ADMIN_SIGNING_SEED_B64=seed456
ACCESS_ASSIGNMENT_ADMIN_AUDIENCE=bff
CHAT_INTERNAL_IDENTITY_PUBLIC_KEYS=pubkey2
PAYMENTS_INTERNAL_IDENTITY_PUBLIC_KEYS=pubkey3
BFF_ROLE_HEADER_SECRET=role-secret-123
ALLOWED_HOSTS=api.shamell.online
ALLOWED_ORIGINS=https://online.shamell.online
ENV=staging
BFF_ENFORCE_ROUTE_AUTHZ=true
BFF_TRUSTED_PROXY_CIDRS=127.0.0.1/32,::1/128
AUTH_ACCEPT_LEGACY_SESSION_COOKIE=false
LIVEKIT_API_KEY=livekit-prod-key
LIVEKIT_API_SECRET=livekit-prod-secret
AUTH_ACCOUNT_CREATE_POW_ENABLED=false
AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED=false
AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION=false
AUTH_ACCOUNT_CREATE_ENABLED=false
AUTH_PAYMENT_MUTATION_HARDWARE_ATTESTATION_ENABLED=false
AUTH_BIOMETRIC_ENROLL_HARDWARE_ATTESTATION_ENABLED=false
AUTH_BIOMETRIC_LOGIN_HARDWARE_ATTESTATION_ENABLED=false
EOF

cp "$valid_env" "$invalid_env"
perl -pi -e 's/^INTERNAL_API_SECRET=.*/INTERNAL_API_SECRET=change-me/' "$invalid_env"

if ! PATH="${tmpbin}:$PATH" ENV_FILE="$valid_env" "$OPS_SCRIPT" pipg sync-nginx shamell >"$ok_out" 2>"$ok_err"; then
  echo "sync-nginx unexpectedly failed on valid synthetic env" >&2
  cat "$ok_err" >&2
  exit 1
fi

if ! grep -q 'Env check OK:' "$ok_out" && ! grep -q 'Env check OK:' "$ok_err"; then
  echo "sync-nginx valid path did not run env preflight" >&2
  cat "$ok_out" >&2
  cat "$ok_err" >&2
  exit 1
fi

if ! grep -q 'Copying Nginx configs to shamell:' "$ok_out"; then
  echo "sync-nginx valid path did not reach sync step after env preflight" >&2
  cat "$ok_out" >&2
  exit 1
fi

set +e
PATH="${tmpbin}:$PATH" ENV_FILE="$invalid_env" "$OPS_SCRIPT" pipg sync-nginx shamell >"$bad_out" 2>"$bad_err"
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "sync-nginx unexpectedly succeeded on invalid env" >&2
  cat "$bad_out" >&2
  cat "$bad_err" >&2
  exit 1
fi

if ! grep -q 'Missing or invalid INTERNAL_API_SECRET' "$bad_err"; then
  echo "sync-nginx invalid path did not fail on env preflight" >&2
  cat "$bad_err" >&2
  exit 1
fi

if grep -q 'Copying Nginx configs to shamell:' "$bad_out"; then
  echo "sync-nginx invalid path reached host mutation steps before env preflight failure" >&2
  cat "$bad_out" >&2
  exit 1
fi

cp "$SNIPPET_PATH" "$stale_snippet"
perl -0pi -e 's/# on \d{4}-\d{2}-\d{2} \(update periodically\)\./# on 2025-01-01 (update periodically)./' "$stale_snippet"

set +e
PATH="${tmpbin}:$PATH" ENV_FILE="$valid_env" CLOUDFLARE_REALIP_SNIPPET="$stale_snippet" "$OPS_SCRIPT" pipg sync-edge shamell >"$bad_out" 2>"$bad_err"
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "sync-edge unexpectedly succeeded with stale Cloudflare snippet" >&2
  cat "$bad_out" >&2
  cat "$bad_err" >&2
  exit 1
fi

if ! grep -q 'Cloudflare real-ip snippet freshness must pass before non-dev check/deploy.' "$bad_err"; then
  echo "sync-edge stale path did not fail through shared edge preflight" >&2
  cat "$bad_err" >&2
  exit 1
fi

if grep -q 'Copying Nginx configs to shamell:' "$bad_out"; then
  echo "sync-edge stale path reached host mutation steps before preflight failure" >&2
  cat "$bad_out" >&2
  exit 1
fi

echo "ops.sh edge preflight check passed."
