#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPS_SCRIPT="${ROOT}/scripts/ops.sh"
SNIPPET_PATH="${ROOT}/ops/hetzner/nginx/snippets/shamell_cloudflare_realip.conf"

tmpbin="$(mktemp -d)"
tmpenv="$(mktemp)"
stale_snippet="$(mktemp)"
fresh_out="$(mktemp)"
fresh_err="$(mktemp)"
fail_out="$(mktemp)"
fail_err="$(mktemp)"

cleanup() {
  rm -rf "$tmpbin" "$tmpenv" "$stale_snippet" "$fresh_out" "$fresh_err" "$fail_out" "$fail_err"
}
trap cleanup EXIT

cat >"${tmpbin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "compose" ]]; then
  shift
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -f|--env-file)
        shift 2
        ;;
      ps)
        echo "NAME IMAGE COMMAND SERVICE CREATED STATUS PORTS"
        exit 0
        ;;
      *)
        shift
        ;;
    esac
  done
fi
exit 0
EOF
chmod +x "${tmpbin}/docker"

cat >"$tmpenv" <<'EOF'
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

if ! PATH="${tmpbin}:$PATH" ENV_FILE="$tmpenv" SKIP_HEALTH_CHECK=1 RIDE_REPORT_FAIL_ON_FINDINGS=0 "$OPS_SCRIPT" pipg report >"$fresh_out" 2>"$fresh_err"; then
  echo "ops report unexpectedly failed on synthetic healthy path" >&2
  cat "$fresh_err" >&2
  exit 1
fi

if grep -q 'Health check failed.' "$fresh_err"; then
  echo "ops report healthy path unexpectedly emitted health failure" >&2
  cat "$fresh_err" >&2
  exit 1
fi

if ! grep -q '==> ride ops' "$fresh_out"; then
  echo "ops report healthy path did not include ride ops section" >&2
  cat "$fresh_out" >&2
  exit 1
fi

cp "$SNIPPET_PATH" "$stale_snippet"
perl -0pi -e 's/# on \d{4}-\d{2}-\d{2} \(update periodically\)\./# on 2025-01-01 (update periodically)./' "$stale_snippet"

set +e
PATH="${tmpbin}:$PATH" ENV_FILE="$tmpenv" HEALTH_URL='http://127.0.0.1:9/health' CLOUDFLARE_REALIP_SNIPPET="$stale_snippet" RIDE_REPORT_FAIL_ON_FINDINGS=0 "$OPS_SCRIPT" pipg report >"$fail_out" 2>"$fail_err"
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "ops report unexpectedly succeeded when health and Cloudflare freshness both failed" >&2
  cat "$fail_err" >&2
  exit 1
fi

if ! grep -q 'Health check failed.' "$fail_err"; then
  echo "ops report failure path did not surface health failure" >&2
  cat "$fail_err" >&2
  exit 1
fi

if ! grep -q 'Cloudflare trusted-proxy CIDR freshness check failed.' "$fail_err"; then
  echo "ops report failure path did not surface Cloudflare freshness failure" >&2
  cat "$fail_err" >&2
  exit 1
fi

echo "ops.sh report exit semantics check passed."
