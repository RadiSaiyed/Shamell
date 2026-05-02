#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${APP_DIR}/scripts/lib_internal_identity.sh"

usage() {
  cat <<'USAGE'
Usage: scripts/ops.sh <env> <command> [args]

env:
  dev    local Rust microservices stack (docker-compose.yml)
  pi     Hetzner stack (alias of pipg)
  pipg   Hetzner stack with Postgres (ops/pi/docker-compose.postgres.yml)
  prod   alias of pipg

commands:
  up            build and start
  down          stop and remove
  restart       restart services
  logs          tail logs (pass service names or flags)
  ps            show status
  report        status + health + disk + backups
  cloudflare-refresh refresh local Cloudflare trusted-proxy CIDRs for edge IaC
  cloudflare-status check local Cloudflare trusted-proxy CIDR freshness
  sync-nginx    sync Hetzner Nginx IaC (passes ops env file by default)
  sync-ufw      sync Hetzner UFW allowlists / origin-lockdown policy
  sync-edge     refresh Cloudflare CIDRs, then sync Nginx + UFW
  smoke-api     run public-vs-internal auth boundary smoke (read-only)
  smoke-mailbox run mailbox transport smoke (non-dev; staging-safe by default)
  smoke-payment-attestation run payment step-up rollout smoke (writes temp auth/payment rows)
  smoke-payments-moneyflow run full payments moneyflow smoke (writes temp auth/payment rows)
  smoke-ride-flow run local ride e2e smoke with isolated temp databases
  ride-report   read-only ride ops audit (stuck matching, stale drivers, stale fee holds)
  ride-repair-stale-presence repair stale online driver presence + cancel pending offers
  ride-release-gate run the canonical ride release gate (dev: local smoke, non-dev: schema + health + smoke-api + ride-report)
  schema-migrate run Rust schema migrator for bff/chat/payments (default: all)
  sync-ride-report-timer install/update Hetzner ride ops audit timer
  matrix-api    run authenticated/unauthenticated API route matrix (non-dev)
  security-report  summarize recent BFF security events and alert on thresholds
  security-drill   send synthetic webhook drill payload
  access-assign  signed internal admin helper for /internal/admin/access/assignments
  build         build images
  pull          pull images
  health        call /health
  check         validate env file (non-dev)
  deploy        check + up + health (non-dev); optional service names narrow the deploy
  migrate       alias of schema-migrate
  backup        backup postgres databases
  restore       restore postgres databases
  shell         shell into primary app container

Environment variables:
  ENV_FILE      override env file for non-dev (default: ops/pi/.env)
  BACKUP_DIR    backup destination (default: backups/)
  BACKUP_KEEP   keep last N backups per type (0 disables pruning)
  CONFIRM_RESTORE=1  allow destructive restore
  RESTORE_DROP_SCHEMA=1  drop public schema before restore
  ALLOW_RUNNING_RESTORE=1 allow restore while services are running
  HEALTH_URL    override health URL
  HEALTH_HOST   optional Host header for health check (pipg/prod default: bff)
  HEALTH_RESOLVE optional curl --resolve (host:port:addr)
  HEALTH_INSECURE=1 allow insecure TLS for health check
  HEALTH_RETRIES  retry health check N times (default: 1)
  HEALTH_RETRY_DELAY  seconds between retries (default: 2)
  SMOKE_BASE_URL override smoke base URL (defaults to HEALTH_URL without /health)
  SMOKE_INSECURE=1 allow insecure TLS for smoke requests (defaults to HEALTH_INSECURE)
  SMOKE_HOST    optional Host header for smoke requests (defaults to HEALTH_HOST)
  SMOKE_RESOLVE optional curl --resolve for smoke requests (defaults to HEALTH_RESOLVE)
  SMOKE_CLIENT_IP optional X-Forwarded-For client IP override for smoke checks; requires BFF_TRUSTED_PROXY_CIDRS to trust the immediate proxy/loopback hop
  SMOKE_ALLOW_PROD=1 allow write-oriented smokes against prod
  SMOKE_PAYMENT_AMOUNT_CENTS amount_cents for payment-attestation smoke (default: 101)
  SMOKE_EXPECT_PAYMENT_ATTESTATION_ENABLED override payment-attestation enabled expectation
  SMOKE_MONEYFLOW_TOPUP_CENTS topup amount_cents for moneyflow smoke (default: 5000)
  SMOKE_MONEYFLOW_TRANSFER_CENTS transfer amount_cents for moneyflow smoke (default: 1200)
  SMOKE_MONEYFLOW_REQUEST_CENTS request amount_cents for moneyflow smoke (default: 333)
  RIDE_REPORT_MATCHING_STALE_SECS seconds before matching rides count as stale (default: 180)
  RIDE_REPORT_MATCHING_NO_OFFER_STALE_SECS seconds before matching rides with no pending offer count as stale (default: 45)
  RIDE_REPORT_PENDING_OFFER_STALE_SECS seconds before pending dispatch offers count as stale (default: 90)
  RIDE_REPORT_DRIVER_PRESENCE_STALE_SECS seconds before online driver presence counts as stale (default: 45)
  RIDE_REPORT_LIVE_STATE_STALE_SECS seconds before active-trip live state counts as stale (default: 45)
  RIDE_REPORT_RESERVED_FEE_HOLD_STALE_SECS seconds before reserved 10%% fee holds count as stale (default: 900)
  RIDE_REPORT_DETAIL_LIMIT maximum rows per finding section (default: 5)
  RIDE_REPORT_FAIL_ON_FINDINGS=1 make ride-report exit non-zero when findings exist
  RIDE_RELEASE_GATE_SKIP_SCHEMA_MIGRATE=1 skip schema-migrate bff/payments in ride-release-gate
  RIDE_RELEASE_GATE_RUN_MATRIX_API=1 append matrix-api to ride-release-gate on non-dev
  SKIP_HEALTH_CHECK=1 skip health check
  DEPLOY_FORCE_SEQUENTIAL_BUILD=1 skip fast compose up --build path for up/deploy
  DEPLOY_SEQUENTIAL_BUILD_SERVICES service list for fallback builds (default: bff chat payments)
  DEPLOY_BUILD_RETRIES retry count per sequential service build (default: 3)
  DEPLOY_BUILD_RETRY_DELAY_SECS seconds between sequential build retries (default: 8)
  SECURITY_ALERT_WINDOW_SECS  security-report lookback window (default: 300)
  SECURITY_ALERT_COOLDOWN_SECS security-report webhook cooldown (default: 600)
  SECURITY_ALERT_THRESHOLDS comma-separated threshold rules
  SECURITY_ALERT_WEBHOOK_URL optional webhook target for security-report alerts
  SECURITY_ALERT_WEBHOOK_INTERNAL_SECRET optional X-Internal-Secret override for webhook posts
  SECURITY_ALERT_WEBHOOK_SERVICE_ID optional X-Internal-Service-Id for webhook posts
  SECURITY_ALERT_WEBHOOK_SIGNING_SEED_B64 optional Ed25519 seed for signed alert webhook posts
  SECURITY_ALERT_WEBHOOK_AUDIENCE optional audience for signed alert webhook posts (default: bff)
  SECURITY_ALERT_SERVICE docker service names to scan (default: bff,chat)
  SECURITY_ALERT_LOG_FILE optional JSON log replay source for security-report (skips docker)
  ACCESS_ASSIGNMENT_ADMIN_BASE_URL optional base URL for access-assign helper (defaults to BFF publish addr/port)
  ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID internal caller id for access-assign helper (default: control-automation)
  ACCESS_ASSIGNMENT_ADMIN_SIGNING_SEED_B64 Ed25519 seed for access-assign helper
  ACCESS_ASSIGNMENT_ADMIN_AUDIENCE audience for access-assign helper (default: bff)
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

ENV_NAME="${1:-}"
CMD="${2:-}"
if [[ -z "$ENV_NAME" || -z "$CMD" ]]; then
  usage
  exit 1
fi
shift 2

case "$ENV_NAME" in
  dev)
    COMPOSE_FILE="${APP_DIR}/docker-compose.yml"
    DEFAULT_ENV_FILE=""
    HEALTH_URL_DEFAULT="http://localhost:8080/health"
    HEALTH_HOST_DEFAULT=""
    PRIMARY_SERVICE="bff"
    ;;
  pi|pipg|pi-pg|pi-postgres|prod)
    COMPOSE_FILE="${APP_DIR}/ops/pi/docker-compose.postgres.yml"
    DEFAULT_ENV_FILE="${APP_DIR}/ops/pi/.env"
    HEALTH_URL_DEFAULT="http://localhost:8080/health"
    HEALTH_HOST_DEFAULT="bff"
    PRIMARY_SERVICE="bff"
    ;;
  *)
    usage
    exit 1
    ;;
esac

ENV_FILE_PATH="${ENV_FILE:-$DEFAULT_ENV_FILE}"
if [[ -n "$ENV_FILE_PATH" && ! -f "$ENV_FILE_PATH" ]]; then
  echo "Env file not found: ${ENV_FILE_PATH}" >&2
  exit 1
fi

compose() {
  require_cmd docker
  if [[ -n "$ENV_FILE_PATH" ]]; then
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE_PATH" "$@"
  else
    docker compose -f "$COMPOSE_FILE" "$@"
  fi
}

read_env() {
  local key="$1"
  if [[ -z "$ENV_FILE_PATH" || ! -f "$ENV_FILE_PATH" ]]; then
    return 0
  fi
  local line
  line="$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE_PATH" | tail -n1 || true)"
  line="${line#*=}"
  line="${line%\"}"
  line="${line#\"}"
  printf "%s" "$line"
}

env_file_has_pattern() {
  local pattern="$1"
  if [[ -z "$ENV_FILE_PATH" || ! -f "$ENV_FILE_PATH" ]]; then
    return 1
  fi
  grep -Eq "$pattern" "$ENV_FILE_PATH"
}

is_false_like() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "0" || "$v" == "false" || "$v" == "off" || "$v" == "no" ]]
}

is_true_like() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "on" || "$v" == "yes" ]]
}

csv_contains_token() {
  local csv="$1"
  local needle="$2"
  local normalized_csv normalized_needle
  local -a items
  normalized_csv="$(printf '%s' "$csv" | tr '[:upper:]' '[:lower:]')"
  normalized_needle="$(printf '%s' "$needle" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  IFS=',' read -r -a items <<<"$normalized_csv"
  local token
  for token in "${items[@]}"; do
    token="$(printf '%s' "$token" | tr -d '[:space:]')"
    if [[ -n "$token" && "$token" == "$normalized_needle" ]]; then
      return 0
    fi
  done
  return 1
}

public_keys_csv_has_service() {
  local csv="$1"
  local service_id="$2"
  local normalized_csv normalized_service key
  local -a entries
  normalized_csv="$(printf '%s' "$csv" | tr '[:upper:]' '[:lower:]')"
  normalized_service="$(printf '%s' "$service_id" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  IFS=',' read -r -a entries <<<"$normalized_csv"
  local pair
  for pair in "${entries[@]}"; do
    key="${pair%%=*}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    if [[ -n "$key" && "$key" == "$normalized_service" ]]; then
      return 0
    fi
  done
  return 1
}

is_placeholder_like() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  [[ -z "$v" || "$v" == change-me* || "$v" == *changeme* || "$v" == *replace-me* || "$v" == *replace_me* || "$v" == *please-rotate* || "$v" == *todo* || "$v" == "<set>" || "$v" == "set-me" || "$v" == "setme" ]]
}

check_env() {
  if [[ "$ENV_NAME" == "dev" ]]; then
    echo "dev env: no env-file checks."
    return 0
  fi

  local missing=0
  local required=(
    POSTGRES_USER
    POSTGRES_PASSWORD
    DB_URL
    CHAT_DB_URL
    PAYMENTS_DB_URL
    INTERNAL_API_SECRET
    BFF_SECURITY_ALERT_INTERNAL_IDENTITY_PUBLIC_KEYS
    BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64
    CHAT_INTERNAL_IDENTITY_PUBLIC_KEYS
    PAYMENTS_INTERNAL_IDENTITY_PUBLIC_KEYS
    BFF_ROLE_HEADER_SECRET
    ALLOWED_HOSTS
    ALLOWED_ORIGINS
  )

  local key val
  for key in "${required[@]}"; do
    val="$(read_env "$key")"
    if is_placeholder_like "$val"; then
      echo "Missing or invalid ${key} in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
  done

  local security_alert_webhook_url security_alert_signing_seed
  security_alert_webhook_url="$(read_env SECURITY_ALERT_WEBHOOK_URL)"
  security_alert_signing_seed="$(read_env SECURITY_ALERT_WEBHOOK_SIGNING_SEED_B64)"
  if [[ "$security_alert_webhook_url" == *"/internal/security/alerts"* ]] &&
    is_placeholder_like "$security_alert_signing_seed"; then
    echo "Missing or invalid SECURITY_ALERT_WEBHOOK_SIGNING_SEED_B64 in ${ENV_FILE_PATH}" >&2
    missing=1
  fi

  for key in DB_URL CHAT_DB_URL PAYMENTS_DB_URL; do
    val="$(read_env "$key")"
    local norm
    norm="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]')"
    if [[ -z "$norm" || ( "$norm" != postgres* && "$norm" != postgresql* ) ]]; then
      echo "${key} must be a postgres URL in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
  done

  local origins hosts
  origins="$(read_env ALLOWED_ORIGINS)"
  hosts="$(read_env ALLOWED_HOSTS)"
  local trusted_proxy_cidrs
  trusted_proxy_cidrs="$(read_env BFF_TRUSTED_PROXY_CIDRS)"
  if [[ "$origins" == *"*"* ]]; then
    echo "ALLOWED_ORIGINS must not include '*' in ${ENV_FILE_PATH}" >&2
    missing=1
  fi
  if [[ "$hosts" == *"*"* ]]; then
    echo "ALLOWED_HOSTS must not include '*' in ${ENV_FILE_PATH}" >&2
    missing=1
  fi

  if ! cloudflare_status; then
    echo "Cloudflare real-ip snippet freshness must pass before non-dev check/deploy." >&2
    missing=1
  fi

  local runtime_env
  runtime_env="$(printf '%s' "$(read_env ENV)" | tr '[:upper:]' '[:lower:]')"
  local access_assignment_callers access_assignment_public_keys access_assignment_require_v2 access_assignment_allow_legacy access_assignment_admin_service_id access_assignment_admin_seed_b64 access_assignment_admin_audience
  access_assignment_callers="$(read_env BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS)"
  access_assignment_public_keys="$(read_env BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS)"
  access_assignment_require_v2="$(read_env BFF_ACCESS_ASSIGNMENT_REQUIRE_INTERNAL_IDENTITY_V2)"
  access_assignment_allow_legacy="$(read_env BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK)"
  access_assignment_admin_service_id="$(read_env ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID)"
  access_assignment_admin_seed_b64="$(read_env ACCESS_ASSIGNMENT_ADMIN_SIGNING_SEED_B64)"
  access_assignment_admin_audience="$(read_env ACCESS_ASSIGNMENT_ADMIN_AUDIENCE)"
  if [[ -n "$access_assignment_callers" ]]; then
    if is_placeholder_like "$access_assignment_public_keys"; then
      echo "Missing or invalid BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if [[ -z "$access_assignment_require_v2" ]] || is_false_like "$access_assignment_require_v2"; then
      echo "BFF_ACCESS_ASSIGNMENT_REQUIRE_INTERNAL_IDENTITY_V2 must be true in ${ENV_FILE_PATH} when BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS is set" >&2
      missing=1
    fi
    if [[ -z "$access_assignment_allow_legacy" ]]; then
      echo "BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK must be false in ${ENV_FILE_PATH} when BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS is set" >&2
      missing=1
    elif ! is_false_like "$access_assignment_allow_legacy"; then
      echo "BFF_ACCESS_ASSIGNMENT_ALLOW_LEGACY_INTERNAL_SECRET_FALLBACK must be false in ${ENV_FILE_PATH} when BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS is set" >&2
      missing=1
    fi
    if is_placeholder_like "$access_assignment_admin_service_id"; then
      echo "Missing or invalid ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if is_placeholder_like "$access_assignment_admin_seed_b64"; then
      echo "Missing or invalid ACCESS_ASSIGNMENT_ADMIN_SIGNING_SEED_B64 in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if is_placeholder_like "$access_assignment_admin_audience"; then
      echo "Missing or invalid ACCESS_ASSIGNMENT_ADMIN_AUDIENCE in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if [[ -n "$access_assignment_admin_service_id" ]] && ! csv_contains_token "$access_assignment_callers" "$access_assignment_admin_service_id"; then
      echo "ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID must appear in BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if [[ -n "$access_assignment_admin_service_id" && -n "$access_assignment_public_keys" ]] && ! public_keys_csv_has_service "$access_assignment_public_keys" "$access_assignment_admin_service_id"; then
      echo "BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS must include ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
  fi
  local payments_allow_direct_topup payments_emergency_direct_topup
  payments_allow_direct_topup="$(read_env PAYMENTS_ALLOW_DIRECT_TOPUP)"
  payments_emergency_direct_topup="$(read_env PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED)"
  if is_true_like "$payments_allow_direct_topup" && is_true_like "$payments_emergency_direct_topup"; then
    echo "PAYMENTS_ALLOW_DIRECT_TOPUP and PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED must not both be true in ${ENV_FILE_PATH}" >&2
    missing=1
  fi
  local route_authz
  route_authz="$(read_env BFF_ENFORCE_ROUTE_AUTHZ)"
  local accept_legacy_cookie
  accept_legacy_cookie="$(read_env AUTH_ACCEPT_LEGACY_SESSION_COOKIE)"
  local allow_header_session_auth
  allow_header_session_auth="$(read_env AUTH_ALLOW_HEADER_SESSION_AUTH)"
  local block_browser_header_session
  block_browser_header_session="$(read_env AUTH_BLOCK_BROWSER_HEADER_SESSION)"
  if [[ "$runtime_env" == "prod" || "$runtime_env" == "production" || "$runtime_env" == "staging" || -z "$runtime_env" ]]; then
    if [[ -z "$route_authz" ]]; then
      echo "BFF_ENFORCE_ROUTE_AUTHZ must be enabled in ${ENV_FILE_PATH} for prod/staging" >&2
      missing=1
    elif is_false_like "$route_authz"; then
      echo "BFF_ENFORCE_ROUTE_AUTHZ must be enabled in ${ENV_FILE_PATH} for prod/staging" >&2
      missing=1
    fi

    if is_true_like "$payments_emergency_direct_topup"; then
      echo "WARN: PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED=true in ${ENV_FILE_PATH} (demo/emergency mode mints wallet funds directly)." >&2
    fi

    if [[ -z "$trusted_proxy_cidrs" ]]; then
      echo "BFF_TRUSTED_PROXY_CIDRS must be set in ${ENV_FILE_PATH} for prod/staging so the BFF can recover real client IPs behind Nginx/proxies" >&2
      missing=1
    fi

    if is_true_like "$accept_legacy_cookie"; then
      echo "AUTH_ACCEPT_LEGACY_SESSION_COOKIE must be false in ${ENV_FILE_PATH} for prod/staging" >&2
      missing=1
    fi

    if [[ -n "$allow_header_session_auth" ]]; then
      echo "AUTH_ALLOW_HEADER_SESSION_AUTH has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if [[ -n "$block_browser_header_session" ]]; then
      echo "AUTH_BLOCK_BROWSER_HEADER_SESSION has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*AUTH_EXPOSE_CODES='; then
      echo "AUTH_EXPOSE_CODES has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*AUTH_REQUEST_CODE_'; then
      echo "AUTH_REQUEST_CODE_* has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*AUTH_VERIFY_'; then
      echo "AUTH_VERIFY_* has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*AUTH_OTP_'; then
      echo "AUTH_OTP_* has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*AUTH_RESOLVE_PHONE_'; then
      echo "AUTH_RESOLVE_PHONE_* has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if env_file_has_pattern '^[[:space:]]*CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP='; then
      echo "CHAT_ALLOW_LEGACY_AUTH_BOOTSTRAP has been removed; delete it from ${ENV_FILE_PATH}" >&2
      missing=1
    fi

    local web_direct_access_origins web_direct_launch_secret web_direct_launch_origins web_direct_launch_effective_origins
    web_direct_access_origins="$(read_env AUTH_WEB_DIRECT_ACCESS_ALLOWED_ORIGINS)"
    web_direct_launch_secret="$(read_env AUTH_WEB_DIRECT_LAUNCH_SIGNING_SECRET)"
    web_direct_launch_origins="$(read_env AUTH_WEB_DIRECT_LAUNCH_ALLOWED_REDIRECT_ORIGINS)"
    web_direct_launch_effective_origins="$web_direct_launch_origins"
    if [[ -z "$web_direct_launch_effective_origins" ]]; then
      web_direct_launch_effective_origins="$web_direct_access_origins"
    fi
    if [[ -n "$web_direct_launch_secret" || -n "$web_direct_launch_effective_origins" ]]; then
      if is_placeholder_like "$web_direct_launch_secret"; then
        echo "AUTH_WEB_DIRECT_LAUNCH_SIGNING_SECRET must be set when direct web launch is enabled in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
      if [[ -z "$web_direct_launch_effective_origins" ]]; then
        echo "AUTH_WEB_DIRECT_LAUNCH_ALLOWED_REDIRECT_ORIGINS must be set when direct web launch is enabled in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
    fi

    local livekit_key livekit_secret
    livekit_key="$(read_env LIVEKIT_API_KEY)"
    livekit_secret="$(read_env LIVEKIT_API_SECRET)"
    if [[ -z "$livekit_key" || -z "$livekit_secret" || "$livekit_key" == "devkey" || "$livekit_secret" == "devsecret" ]]; then
      echo "LIVEKIT_API_KEY/LIVEKIT_API_SECRET must be set to non-dev values in ${ENV_FILE_PATH}" >&2
      missing=1
    fi

    local account_create_pow_enabled
    account_create_pow_enabled="$(read_env AUTH_ACCOUNT_CREATE_POW_ENABLED)"
    if [[ -z "$account_create_pow_enabled" ]]; then
      account_create_pow_enabled="true"
    fi

    if ! is_false_like "$account_create_pow_enabled"; then
      local account_create_pow_secret
      account_create_pow_secret="$(read_env AUTH_ACCOUNT_CREATE_POW_SECRET)"
      if is_placeholder_like "$account_create_pow_secret"; then
        echo "AUTH_ACCOUNT_CREATE_POW_SECRET must be set to a strong non-placeholder value in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
    fi

    local hw_attestation_enabled payment_mutation_hw_attestation_enabled biometric_enroll_hw_attestation_enabled biometric_login_hw_attestation_enabled any_hw_attestation_enabled
    hw_attestation_enabled="$(read_env AUTH_ACCOUNT_CREATE_HARDWARE_ATTESTATION_ENABLED)"
    if [[ -z "$hw_attestation_enabled" ]]; then
      hw_attestation_enabled="true"
    fi
    payment_mutation_hw_attestation_enabled="$(read_env AUTH_PAYMENT_MUTATION_HARDWARE_ATTESTATION_ENABLED)"
    if [[ -z "$payment_mutation_hw_attestation_enabled" ]]; then
      payment_mutation_hw_attestation_enabled="false"
    fi
    biometric_enroll_hw_attestation_enabled="$(read_env AUTH_BIOMETRIC_ENROLL_HARDWARE_ATTESTATION_ENABLED)"
    if [[ -z "$biometric_enroll_hw_attestation_enabled" ]]; then
      biometric_enroll_hw_attestation_enabled="false"
    fi
    biometric_login_hw_attestation_enabled="$(read_env AUTH_BIOMETRIC_LOGIN_HARDWARE_ATTESTATION_ENABLED)"
    if [[ -z "$biometric_login_hw_attestation_enabled" ]]; then
      biometric_login_hw_attestation_enabled="false"
    fi
    local account_create_enabled
    account_create_enabled="$(read_env AUTH_ACCOUNT_CREATE_ENABLED)"
    local hw_attestation_required
    hw_attestation_required="$(read_env AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION)"
    if [[ -z "$hw_attestation_required" ]]; then
      hw_attestation_required="$hw_attestation_enabled"
    fi
    if is_false_like "$hw_attestation_enabled" && is_false_like "$payment_mutation_hw_attestation_enabled" && is_false_like "$biometric_enroll_hw_attestation_enabled" && is_false_like "$biometric_login_hw_attestation_enabled"; then
      any_hw_attestation_enabled="false"
    else
      any_hw_attestation_enabled="true"
    fi

    local apple_team_id apple_key_id apple_p8_b64
    apple_team_id="$(read_env AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID)"
    apple_key_id="$(read_env AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID)"
    apple_p8_b64="$(read_env AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64)"

    local play_svc_b64 play_pkgs play_require_strong play_require_recognized play_require_licensed
    play_svc_b64="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64)"
    play_pkgs="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES)"
    play_require_strong="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY)"
    play_require_recognized="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED)"
    play_require_licensed="$(read_env AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED)"

    local apple_any apple_configured play_any play_configured hw_provider_configured
    apple_any=0
    apple_configured=0
    play_any=0
    play_configured=0
    hw_provider_configured=0
    if [[ -n "$apple_team_id" || -n "$apple_key_id" || -n "$apple_p8_b64" ]]; then
      apple_any=1
    fi
    if [[ -n "$apple_team_id" && -n "$apple_key_id" && -n "$apple_p8_b64" ]]; then
      apple_configured=1
      hw_provider_configured=1
    fi
    if [[ -n "$play_svc_b64" || -n "$play_pkgs" ]]; then
      play_any=1
    fi
    if [[ -n "$play_svc_b64" && -n "$play_pkgs" ]]; then
      play_configured=1
      hw_provider_configured=1
    fi

    if is_false_like "$hw_attestation_enabled"; then
      if [[ -n "$hw_attestation_required" ]] && ! is_false_like "$hw_attestation_required"; then
        echo "AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION must be false in ${ENV_FILE_PATH} when account-create hardware attestation is disabled" >&2
        missing=1
      fi
      if [[ -z "$account_create_enabled" ]] || ! is_false_like "$account_create_enabled"; then
        echo "AUTH_ACCOUNT_CREATE_ENABLED must be explicitly false in ${ENV_FILE_PATH} when account-create hardware attestation is disabled (secure interim mode)" >&2
        missing=1
      fi
    elif is_false_like "$hw_attestation_required"; then
      echo "AUTH_ACCOUNT_CREATE_REQUIRE_HARDWARE_ATTESTATION must be true in ${ENV_FILE_PATH} for prod/staging strict mode" >&2
      missing=1
    fi

    if is_false_like "$any_hw_attestation_enabled"; then
      if (( apple_any == 1 )); then
        echo "Apple DeviceCheck vars must be empty in ${ENV_FILE_PATH} when hardware attestation is disabled for all auth surfaces" >&2
        missing=1
      fi
      if (( play_any == 1 )); then
        echo "Play Integrity provider vars must be empty in ${ENV_FILE_PATH} when hardware attestation is disabled for all auth surfaces" >&2
        missing=1
      fi
      if [[ -n "$play_require_strong" ]] && ! is_false_like "$play_require_strong"; then
        echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY must be false in ${ENV_FILE_PATH} when hardware attestation is disabled for all auth surfaces" >&2
        missing=1
      fi
      if [[ -n "$play_require_recognized" ]] && ! is_false_like "$play_require_recognized"; then
        echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED must be false in ${ENV_FILE_PATH} when hardware attestation is disabled for all auth surfaces" >&2
        missing=1
      fi
      if [[ -n "$play_require_licensed" ]] && ! is_false_like "$play_require_licensed"; then
        echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_LICENSED must be false in ${ENV_FILE_PATH} when hardware attestation is disabled for all auth surfaces" >&2
        missing=1
      fi
    else
      if (( apple_any == 1 && apple_configured == 0 )); then
        echo "Apple DeviceCheck vars must all be set together in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
      if (( play_any == 1 && play_configured == 0 )); then
        echo "Play Integrity provider vars must all be set together in ${ENV_FILE_PATH}" >&2
        missing=1
      fi
      if (( hw_provider_configured == 0 )); then
        echo "At least one hardware attestation provider must be configured in ${ENV_FILE_PATH} when account-create, payment, biometric-enroll, or biometric-login attestation is enabled" >&2
        missing=1
      fi

      if (( apple_configured == 1 )); then
        if is_placeholder_like "$apple_team_id"; then
          echo "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_TEAM_ID must be set in ${ENV_FILE_PATH}" >&2
          missing=1
        fi
        if is_placeholder_like "$apple_key_id"; then
          echo "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_KEY_ID must be set in ${ENV_FILE_PATH}" >&2
          missing=1
        fi
        if is_placeholder_like "$apple_p8_b64"; then
          echo "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 must be set in ${ENV_FILE_PATH}" >&2
          missing=1
        elif command -v openssl >/dev/null 2>&1; then
          if ! printf '%s' "$apple_p8_b64" | openssl base64 -d -A >/dev/null 2>&1; then
            echo "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 must be valid base64 PEM in ${ENV_FILE_PATH}" >&2
            missing=1
          else
            local apple_decoded
            apple_decoded="$(printf '%s' "$apple_p8_b64" | openssl base64 -d -A 2>/dev/null || true)"
            if [[ "$apple_decoded" != *"BEGIN PRIVATE KEY"* ]]; then
              echo "AUTH_ACCOUNT_CREATE_APPLE_DEVICECHECK_PRIVATE_KEY_P8_B64 must decode to a PEM private key in ${ENV_FILE_PATH}" >&2
              missing=1
            fi
          fi
        fi
      fi

      if (( play_configured == 1 )); then
        if is_placeholder_like "$play_svc_b64"; then
          echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 must be set in ${ENV_FILE_PATH}" >&2
          missing=1
        elif command -v openssl >/dev/null 2>&1; then
          if ! printf '%s' "$play_svc_b64" | openssl base64 -d -A >/dev/null 2>&1; then
            echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 must be valid base64(JSON) in ${ENV_FILE_PATH}" >&2
            missing=1
          else
            local play_decoded
            play_decoded="$(printf '%s' "$play_svc_b64" | openssl base64 -d -A 2>/dev/null || true)"
            if [[ "$play_decoded" != *"\"client_email\""* || "$play_decoded" != *"\"private_key\""* ]]; then
              echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON_B64 must include client_email/private_key in ${ENV_FILE_PATH}" >&2
              missing=1
            fi
          fi
        fi

        if is_placeholder_like "$play_pkgs"; then
          echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_ALLOWED_PACKAGE_NAMES must be set in ${ENV_FILE_PATH}" >&2
          missing=1
        fi
        if [[ -z "$play_require_strong" ]] || is_false_like "$play_require_strong"; then
          echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_STRONG_INTEGRITY must be true in ${ENV_FILE_PATH}" >&2
          missing=1
        fi
        if [[ -z "$play_require_recognized" ]] || is_false_like "$play_require_recognized"; then
          echo "AUTH_ACCOUNT_CREATE_GOOGLE_PLAY_INTEGRITY_REQUIRE_PLAY_RECOGNIZED must be true in ${ENV_FILE_PATH}" >&2
          missing=1
        fi
      fi
    fi

    if (( hw_provider_configured == 0 )) && ! is_false_like "$payment_mutation_hw_attestation_enabled"; then
      echo "AUTH_PAYMENT_MUTATION_HARDWARE_ATTESTATION_ENABLED=true requires at least one configured hardware-attestation provider in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if (( hw_provider_configured == 0 )) && ! is_false_like "$biometric_enroll_hw_attestation_enabled"; then
      echo "AUTH_BIOMETRIC_ENROLL_HARDWARE_ATTESTATION_ENABLED=true requires at least one configured hardware-attestation provider in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
    if (( hw_provider_configured == 0 )) && ! is_false_like "$biometric_login_hw_attestation_enabled"; then
      echo "AUTH_BIOMETRIC_LOGIN_HARDWARE_ATTESTATION_ENABLED=true requires at least one configured hardware-attestation provider in ${ENV_FILE_PATH}" >&2
      missing=1
    fi

    if (( hw_provider_configured == 0 )) && { [[ -z "$account_create_enabled" ]] || ! is_false_like "$account_create_enabled"; }; then
      echo "AUTH_ACCOUNT_CREATE_ENABLED=true requires hardware attestation to be enabled, required, and backed by at least one provider in ${ENV_FILE_PATH}" >&2
      missing=1
    fi
  fi

  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
  echo "Env check OK: ${ENV_FILE_PATH}"
}

health() {
  if [[ "${SKIP_HEALTH_CHECK:-0}" == "1" ]]; then
    echo "Health check skipped."
    return 0
  fi

  require_cmd curl

  local url="${HEALTH_URL:-$HEALTH_URL_DEFAULT}"
  local health_host="${HEALTH_HOST:-$HEALTH_HOST_DEFAULT}"
  local curl_args=(-fsS)
  if [[ "${HEALTH_INSECURE:-0}" == "1" ]]; then
    curl_args+=(-k)
  fi
  if [[ -n "$health_host" ]]; then
    curl_args+=(-H "Host: ${health_host}")
  fi
  if [[ -n "${HEALTH_RESOLVE:-}" ]]; then
    curl_args+=(--resolve "${HEALTH_RESOLVE}")
  fi

  local retries="${HEALTH_RETRIES:-1}"
  local delay="${HEALTH_RETRY_DELAY:-2}"
  local attempt=1

  while true; do
    if curl "${curl_args[@]}" "$url"; then
      echo
      return 0
    fi
    if (( attempt >= retries )); then
      break
    fi
    sleep "$delay"
    attempt=$((attempt + 1))
  done

  return 1
}

prune_backups() {
  local backup_dir="$1"
  local pattern="$2"
  local keep="${BACKUP_KEEP:-0}"
  if [[ -z "$keep" || "$keep" == "0" ]]; then
    return 0
  fi
  if ! [[ "$keep" =~ ^[0-9]+$ ]]; then
    echo "BACKUP_KEEP must be an integer." >&2
    exit 1
  fi

  local files=()
  local f
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$backup_dir" -maxdepth 1 -type f -name "$pattern" -print | sort -r)

  if (( ${#files[@]} <= keep )); then
    return 0
  fi

  local idx
  for ((idx=keep; idx<${#files[@]}; idx++)); do
    rm -f "${files[idx]}"
    echo "Pruned: ${files[idx]}"
  done
}

_pg_read_or() {
  local key="$1"
  local default="$2"
  local v
  v="$(read_env "$key")"
  if [[ -z "$v" ]]; then
    v="$default"
  fi
  printf "%s" "$v"
}

backup_postgres_bundle() {
  local backup_dir="$1"
  local ts="$2"

  local user password
  user="$(read_env POSTGRES_USER)"
  password="$(read_env POSTGRES_PASSWORD)"
  if [[ -z "$user" || -z "$password" ]]; then
    echo "Missing POSTGRES_USER/POSTGRES_PASSWORD in ${ENV_FILE_PATH}" >&2
    exit 1
  fi

  local core_db chat_db payments_db
  core_db="$(_pg_read_or POSTGRES_DB_CORE shamell_core)"
  chat_db="$(_pg_read_or POSTGRES_DB_CHAT shamell_chat)"
  payments_db="$(_pg_read_or POSTGRES_DB_PAYMENTS shamell_payments)"

  local out="${backup_dir}/${ENV_NAME}-postgres-${ts}.tar.gz"
  local tmp
  tmp="$(mktemp -d)"

  compose up -d db >/dev/null

  compose exec -T --env PGPASSWORD="$password" db pg_dump -U "$user" -d "$core_db" --no-owner --no-privileges > "${tmp}/core.sql"
  compose exec -T --env PGPASSWORD="$password" db pg_dump -U "$user" -d "$chat_db" --no-owner --no-privileges > "${tmp}/chat.sql"
  compose exec -T --env PGPASSWORD="$password" db pg_dump -U "$user" -d "$payments_db" --no-owner --no-privileges > "${tmp}/payments.sql"

  tar -czf "$out" -C "$tmp" core.sql chat.sql payments.sql
  rm -rf "$tmp" || true

  echo "Backup written: ${out}"
  prune_backups "$backup_dir" "${ENV_NAME}-postgres-*.tar.gz"
}

restore_postgres_bundle() {
  local backup_file="$1"

  local user password
  user="$(read_env POSTGRES_USER)"
  password="$(read_env POSTGRES_PASSWORD)"
  if [[ -z "$user" || -z "$password" ]]; then
    echo "Missing POSTGRES_USER/POSTGRES_PASSWORD in ${ENV_FILE_PATH}" >&2
    exit 1
  fi

  local core_db chat_db payments_db
  core_db="$(_pg_read_or POSTGRES_DB_CORE shamell_core)"
  chat_db="$(_pg_read_or POSTGRES_DB_CHAT shamell_chat)"
  payments_db="$(_pg_read_or POSTGRES_DB_PAYMENTS shamell_payments)"

  local tmp
  tmp="$(mktemp -d)"
  tar -xzf "$backup_file" -C "$tmp"

  for f in core.sql chat.sql payments.sql; do
    if [[ ! -f "${tmp}/${f}" ]]; then
      echo "Invalid postgres backup bundle (missing ${f}): ${backup_file}" >&2
      exit 1
    fi
  done

  compose up -d db >/dev/null

  if [[ "${RESTORE_DROP_SCHEMA:-0}" == "1" ]]; then
    for db in "$core_db" "$chat_db" "$payments_db"; do
      compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$db" -v ON_ERROR_STOP=1 -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
    done
  fi

  cat "${tmp}/core.sql" | compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$core_db" -v ON_ERROR_STOP=1
  cat "${tmp}/chat.sql" | compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$chat_db" -v ON_ERROR_STOP=1
  cat "${tmp}/payments.sql" | compose exec -T --env PGPASSWORD="$password" db psql -U "$user" -d "$payments_db" -v ON_ERROR_STOP=1

  rm -rf "$tmp" || true
  echo "Restore complete: ${backup_file}"
}

backup() {
  local backup_dir="${BACKUP_DIR:-${APP_DIR}/backups}"
  mkdir -p "$backup_dir"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  backup_postgres_bundle "$backup_dir" "$ts"
}

restore() {
  local backup_file="${1:-}"
  if [[ -z "$backup_file" ]]; then
    echo "Usage: scripts/ops.sh ${ENV_NAME} restore <backup-file>" >&2
    exit 1
  fi
  if [[ ! -f "$backup_file" ]]; then
    echo "Backup not found: ${backup_file}" >&2
    exit 1
  fi
  if [[ "${CONFIRM_RESTORE:-0}" != "1" ]]; then
    echo "Refusing to restore without CONFIRM_RESTORE=1" >&2
    exit 1
  fi

  local running
  running="$(compose ps -q bff || true)"
  if [[ -n "$running" && "${ALLOW_RUNNING_RESTORE:-0}" != "1" ]]; then
    echo "Services are running. Stop them or set ALLOW_RUNNING_RESTORE=1 to proceed." >&2
    exit 1
  fi

  restore_postgres_bundle "$backup_file"
}

report() {
  local backup_dir="${BACKUP_DIR:-${APP_DIR}/backups}"
  local failed=0

  echo "==> status"
  compose ps
  echo

  echo "==> health"
  if ! health; then
    echo "Health check failed." >&2
    failed=1
  fi
  echo

  echo "==> disk"
  if command -v df >/dev/null 2>&1; then
    df -h "$backup_dir" 2>/dev/null || df -h .
  else
    echo "df not available"
  fi
  echo

  echo "==> backups"
  if [[ -d "$backup_dir" ]]; then
    ls -lt "$backup_dir" | head -n 20
  else
    echo "No backups directory at ${backup_dir}"
  fi
  echo

  if [[ "$ENV_NAME" != "dev" ]]; then
    echo "==> edge"
    if ! cloudflare_status; then
      echo "Cloudflare trusted-proxy CIDR freshness check failed." >&2
      failed=1
    fi
    echo

    echo "==> ride ops"
    local ride_report_fail_on_findings="${RIDE_REPORT_FAIL_ON_FINDINGS:-1}"
    if ! RIDE_REPORT_FAIL_ON_FINDINGS="$ride_report_fail_on_findings" ride_report; then
      echo "Ride ops report failed." >&2
      failed=1
    fi
  fi

  if [[ "$failed" -ne 0 ]]; then
    return 1
  fi
}

security_report() {
  "${APP_DIR}/scripts/security_events_report.sh" "$@"
}

security_drill() {
  "${APP_DIR}/scripts/security_alert_webhook_drill.sh" "$@"
}

access_assign() {
  ENV_FILE="${ENV_FILE_PATH}" "${APP_DIR}/scripts/access_assignment_admin.sh" "$@"
}

require_non_dev_edge_command() {
  local cmd_name="$1"
  if [[ "$ENV_NAME" == "dev" ]]; then
    echo "${cmd_name}: run against pipg/prod env; local dev does not manage the Hetzner edge host." >&2
    exit 1
  fi
}

require_non_dev_edge_preflight() {
  local cmd_name="$1"
  require_non_dev_edge_command "$cmd_name"
  check_env
}

cloudflare_refresh() {
  "${APP_DIR}/scripts/update_cloudflare_ip_ranges.sh" "$@"
}

cloudflare_status() {
  "${APP_DIR}/scripts/check_cloudflare_realip_freshness.sh" "$@"
}

sync_nginx() {
  require_non_dev_edge_preflight "sync-nginx"
  if [[ -n "$ENV_FILE_PATH" ]]; then
    NGINX_SYNC_ENV_FILE="$ENV_FILE_PATH" "${APP_DIR}/scripts/sync_hetzner_nginx.sh" "$@"
  else
    "${APP_DIR}/scripts/sync_hetzner_nginx.sh" "$@"
  fi
}

sync_ufw() {
  require_non_dev_edge_command "sync-ufw"
  "${APP_DIR}/scripts/sync_hetzner_ufw.sh" "$@"
}

sync_edge() {
  require_non_dev_edge_preflight "sync-edge"

  local host_alias=""
  local arg
  local -a ufw_args=()
  for arg in "$@"; do
    case "$arg" in
      --allow-livekit|--direct-web)
        ufw_args+=("$arg")
        ;;
      -*)
        echo "sync-edge: unsupported flag: ${arg}" >&2
        echo "sync-edge: supported flags are --allow-livekit and --direct-web." >&2
        exit 1
        ;;
      *)
        if [[ -n "$host_alias" ]]; then
          echo "sync-edge: expected at most one host alias, got extra argument: ${arg}" >&2
          exit 1
        fi
        host_alias="$arg"
        ufw_args+=("$arg")
        ;;
    esac
  done

  cloudflare_refresh
  if [[ -n "$host_alias" ]]; then
    sync_nginx "$host_alias"
  else
    sync_nginx
  fi
  if [[ "${#ufw_args[@]}" -gt 0 ]]; then
    sync_ufw "${ufw_args[@]}"
  else
    sync_ufw
  fi
}

sync_ride_report_timer() {
  require_non_dev_edge_preflight "sync-ride-report-timer"
  "${APP_DIR}/scripts/sync_hetzner_ride_report_timer.sh" "$@"
}

schema_migrate() {
  local target="${1:-all}"
  local services=()

  case "$target" in
    all)
      services=(bff chat payments)
      ;;
    bff|auth)
      services=(bff)
      ;;
    chat)
      services=(chat)
      ;;
    payments|pay)
      services=(payments)
      ;;
    *)
      echo "schema-migrate: unknown target '${target}' (expected: all, bff, chat, payments)." >&2
      return 1
      ;;
  esac

  local service binary
  for service in "${services[@]}"; do
    case "$service" in
      bff) binary="/usr/local/bin/shamell_bff_auth_schema_migrate" ;;
      chat) binary="/usr/local/bin/shamell_chat_schema_migrate" ;;
      payments) binary="/usr/local/bin/shamell_payments_schema_migrate" ;;
      *)
        echo "schema-migrate: unsupported service '${service}'." >&2
        return 1
        ;;
    esac
    echo "schema-migrate: ${service} via ${binary}"
    compose run --rm --no-deps "$service" "$binary"
  done
}

# shellcheck disable=SC2120
# `migrate` is invoked indirectly via the dispatch table near the bottom
# of this script (cmd "$@"), so shellcheck cannot see the call site.
migrate() {
  schema_migrate "$@"
}

compose_build_service() {
  local service="$1"
  if compose build --help 2>/dev/null | grep -q -- '--no-deps'; then
    compose build --no-deps "$service"
  else
    compose build "$service"
  fi
}

sequential_service_build() {
  local services_raw retries delay
  services_raw="${1:-${DEPLOY_SEQUENTIAL_BUILD_SERVICES:-bff chat payments}}"
  retries="${DEPLOY_BUILD_RETRIES:-3}"
  delay="${DEPLOY_BUILD_RETRY_DELAY_SECS:-8}"

  if ! [[ "$retries" =~ ^[0-9]+$ ]] || [[ "$retries" == "0" ]]; then
    echo "DEPLOY_BUILD_RETRIES must be a positive integer." >&2
    return 1
  fi
  if ! [[ "$delay" =~ ^[0-9]+$ ]]; then
    echo "DEPLOY_BUILD_RETRY_DELAY_SECS must be a non-negative integer." >&2
    return 1
  fi

  services_raw="${services_raw//,/ }"
  local build_services=()
  read -r -a build_services <<<"$services_raw"
  if [[ "${#build_services[@]}" -eq 0 ]]; then
    echo "DEPLOY_SEQUENTIAL_BUILD_SERVICES resolved to an empty service list." >&2
    return 1
  fi

  local service attempt
  for service in "${build_services[@]}"; do
    attempt=1
    while true; do
      echo "Sequential build: ${service} (attempt ${attempt}/${retries})"
      if compose_build_service "$service"; then
        break
      fi
      if (( attempt >= retries )); then
        echo "Sequential build failed for ${service} after ${retries} attempts." >&2
        return 1
      fi
      if (( delay > 0 )); then
        echo "Retrying ${service} in ${delay}s..."
        sleep "$delay"
      fi
      attempt=$((attempt + 1))
    done
  done
}

infer_up_build_services() {
  if [[ -n "${DEPLOY_SEQUENTIAL_BUILD_SERVICES:-}" ]]; then
    printf "%s" "${DEPLOY_SEQUENTIAL_BUILD_SERVICES}"
    return 0
  fi

  local -a buildable=(bff chat payments)
  local -a selected=()
  local arg service existing seen
  for arg in "$@"; do
    if [[ "$arg" == -* ]]; then
      continue
    fi
    for service in "${buildable[@]}"; do
      if [[ "$arg" != "$service" ]]; then
        continue
      fi
      seen=0
      if (( ${#selected[@]} > 0 )); then
        for existing in "${selected[@]}"; do
          if [[ "$existing" == "$service" ]]; then
            seen=1
            break
          fi
        done
      fi
      if (( seen == 0 )); then
        selected+=("$service")
      fi
      break
    done
  done

  if [[ "${#selected[@]}" -eq 0 ]]; then
    printf "%s" "${buildable[*]}"
  else
    printf "%s" "${selected[*]}"
  fi
}

compose_up_with_build_fallback() {
  local mode="${1:-Deploy}"
  shift || true
  local -a up_args=()
  local has_up_args=0
  if (( $# > 0 )); then
    up_args=("$@")
    has_up_args=1
  fi
  local force_sequential
  force_sequential="${DEPLOY_FORCE_SEQUENTIAL_BUILD:-0}"
  local build_services
  if (( has_up_args == 1 )); then
    build_services="$(infer_up_build_services "${up_args[@]}")"
  else
    build_services="$(infer_up_build_services)"
  fi

  if is_true_like "$force_sequential"; then
    echo "${mode}: DEPLOY_FORCE_SEQUENTIAL_BUILD enabled; skipping fast build path."
    sequential_service_build "$build_services"
    if (( has_up_args == 1 )); then
      if compose up --help 2>/dev/null | grep -q -- '--no-deps'; then
        compose up -d --no-deps "${up_args[@]}"
      else
        compose up -d "${up_args[@]}"
      fi
    else
      compose up -d
    fi
    return 0
  fi

  if (( has_up_args == 1 )); then
    if compose_build_with_fallback "${mode} build" "${up_args[@]}"; then
      if compose up --help 2>/dev/null | grep -q -- '--no-deps'; then
        compose up -d --no-deps "${up_args[@]}"
      else
        compose up -d "${up_args[@]}"
      fi
      echo "${mode}: targeted build + up path succeeded."
      return 0
    fi
  elif compose up -d --build; then
    echo "${mode}: fast compose up --build path succeeded."
    return 0
  fi

  echo "${mode}: fast compose up path failed; falling back to sequential service builds."
  sequential_service_build "$build_services"
  if (( has_up_args == 1 )); then
    if compose up --help 2>/dev/null | grep -q -- '--no-deps'; then
      compose up -d --no-deps "${up_args[@]}"
    else
      compose up -d "${up_args[@]}"
    fi
  else
    compose up -d
  fi
}

compose_build_with_fallback() {
  local mode="${1:-Build}"
  shift || true
  local -a build_args=()
  local has_build_args=0
  if (( $# > 0 )); then
    build_args=("$@")
    has_build_args=1
  fi
  local force_sequential
  force_sequential="${DEPLOY_FORCE_SEQUENTIAL_BUILD:-0}"
  local build_services
  if (( has_build_args == 1 )); then
    build_services="$(infer_up_build_services "${build_args[@]}")"
  else
    build_services="$(infer_up_build_services)"
  fi

  if is_true_like "$force_sequential"; then
    echo "${mode}: DEPLOY_FORCE_SEQUENTIAL_BUILD enabled; skipping fast compose build path."
    sequential_service_build "$build_services"
    return 0
  fi

  if (( has_build_args == 1 )); then
    if compose build "${build_args[@]}"; then
      echo "${mode}: fast compose build path succeeded."
      return 0
    fi
  elif compose build; then
    echo "${mode}: fast compose build path succeeded."
    return 0
  fi

  echo "${mode}: fast compose build path failed; falling back to sequential service builds."
  sequential_service_build "$build_services"
}

deploy() {
  if [[ "$ENV_NAME" != "dev" ]]; then
    check_env
  fi

  compose_up_with_build_fallback "Deploy" "$@"

  if [[ -z "${HEALTH_RETRIES:-}" ]]; then
    HEALTH_RETRIES=10
  fi
  if [[ -z "${HEALTH_RETRY_DELAY:-}" ]]; then
    HEALTH_RETRY_DELAY=2
  fi
  health
}

smoke_mailbox() {
  if [[ "$ENV_NAME" == "dev" ]]; then
    echo "smoke-mailbox: run against pipg/prod env (needs Postgres-backed auth + internal headers)." >&2
    exit 1
  fi

  require_cmd curl
  require_cmd jq
  require_cmd shasum
  require_cmd openssl

  local env_lower
  env_lower="$(read_env ENV | tr '[:upper:]' '[:lower:]')"
  if [[ "$env_lower" == "prod" || "$env_lower" == "production" ]]; then
    if ! is_true_like "${SMOKE_ALLOW_PROD:-0}"; then
      echo "smoke-mailbox: refusing to write test sessions in prod. Set SMOKE_ALLOW_PROD=1 to override." >&2
      exit 1
    fi
  fi

  local bff_port caller internal_secret client_ip phone device_id sid sid_hash pub envelope
  bff_port="$(read_env BFF_PUBLISH_PORT)"
  bff_port="${bff_port:-8080}"
  internal_secret="$(read_env INTERNAL_API_SECRET)"
  caller="${SMOKE_INTERNAL_CALLER:-edge}"
  caller="$(internal_identity_normalize_service_id "$caller")"

  client_ip="${SMOKE_CLIENT_IP:-203.0.113.10}"
  phone="${SMOKE_PHONE:-+15555550100}"
  device_id="${SMOKE_DEVICE_ID:-smk$(date +%s | tail -c 6)}"

  sid="$(openssl rand -hex 16)"
  sid_hash="$(printf '%s' "$sid" | shasum -a 256 | awk '{print $1}')"

  # 32+ chars; chat service only checks length here.
  pub="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789AB"
  # Must pass normalize_key_material min_len=16 and allowed chars.
  envelope="QUJDREVGR0hJSktMTU5PUFFSU1RVVldY"

  local pg_user pg_pass pg_db
  pg_user="$(read_env POSTGRES_USER)"
  pg_pass="$(read_env POSTGRES_PASSWORD)"
  pg_db="$(read_env POSTGRES_DB_CORE)"
  pg_user="${pg_user:-shamell}"
  pg_db="${pg_db:-shamell_core}"
  if [[ -z "$pg_pass" ]]; then
    echo "smoke-mailbox: missing POSTGRES_PASSWORD in env file." >&2
    exit 1
  fi
  if [[ -z "$internal_secret" ]]; then
    echo "smoke-mailbox: missing INTERNAL_API_SECRET in env file." >&2
    exit 1
  fi

  cleanup_smoke_mailbox() {
    # best-effort cleanup
    local pg_user="${SMOKE_MB_PG_USER:-}"
    local pg_pass="${SMOKE_MB_PG_PASS:-}"
    local pg_db="${SMOKE_MB_PG_DB:-}"
    local sid_hash="${SMOKE_MB_SID_HASH:-}"
    local phone="${SMOKE_MB_PHONE:-}"
    local device_id="${SMOKE_MB_DEVICE_ID:-}"
    if [[ -z "$pg_user" || -z "$pg_pass" || -z "$pg_db" || -z "$sid_hash" ]]; then
      return 0
    fi
    compose exec -T db sh -lc "PGPASSWORD='${pg_pass}' psql -U '${pg_user}' -d '${pg_db}' -v ON_ERROR_STOP=1 -q \
      -c \"DELETE FROM auth_sessions WHERE sid_hash='${sid_hash}';\" \
      -c \"DELETE FROM device_sessions WHERE phone='${phone}' AND device_id='${device_id}';\"" >/dev/null 2>&1 || true
  }
  SMOKE_MB_PG_USER="$pg_user"
  SMOKE_MB_PG_PASS="$pg_pass"
  SMOKE_MB_PG_DB="$pg_db"
  SMOKE_MB_SID_HASH="$sid_hash"
  SMOKE_MB_PHONE="$phone"
  SMOKE_MB_DEVICE_ID="$device_id"
  trap cleanup_smoke_mailbox EXIT

  # Seed session + owned device for BFF guardrails.
  compose exec -T db sh -lc "PGPASSWORD='${pg_pass}' psql -U '${pg_user}' -d '${pg_db}' -v ON_ERROR_STOP=1 -q" >/dev/null <<SQL
INSERT INTO auth_sessions (sid_hash, phone, device_id, expires_at, created_at, last_seen_at, revoked_at)
VALUES ('${sid_hash}', '${phone}', '${device_id}', NOW() + INTERVAL '1 day', NOW(), NOW(), NULL)
ON CONFLICT (sid_hash) DO UPDATE SET phone=EXCLUDED.phone, device_id=EXCLUDED.device_id, expires_at=EXCLUDED.expires_at, last_seen_at=NOW(), revoked_at=NULL;

DELETE FROM device_sessions WHERE phone='${phone}' AND device_id='${device_id}';

INSERT INTO device_sessions (phone, device_id, device_type, device_name, platform, app_version, last_ip, user_agent, created_at, last_seen_at)
VALUES ('${phone}', '${device_id}', 'mobile', 'smoke', 'ios', '1.0', '${client_ip}', 'smoke-mailbox', NOW(), NOW())
;
SQL

  local bff_url
  bff_url="${SMOKE_BFF_URL:-http://127.0.0.1:${bff_port}}"

  local -a common_headers=(
    -H "x-internal-secret: ${internal_secret}"
    -H "x-internal-service-id: ${caller}"
    -H "x-forwarded-for: ${client_ip}"
    -H "content-type: application/json"
    -H "cookie: __Host-sa_session=${sid}"
  )

  local reg_raw reg_http reg_json auth_token
  reg_raw="$(curl -sS -w '\nHTTP:%{http_code}\n' "${common_headers[@]}" \
    -d "{\"device_id\":\"${device_id}\",\"public_key_b64\":\"${pub}\",\"name\":\"smoke\"}" \
    "${bff_url}/chat/devices/register")"
  reg_http="$(printf '%s' "$reg_raw" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  reg_json="$(printf '%s' "$reg_raw" | sed '/^HTTP:/d')"
  auth_token="$(printf '%s' "$reg_json" | jq -r '.auth_token // empty')"
  if [[ "$reg_http" != "200" || -z "$auth_token" ]]; then
    echo "smoke-mailbox: register failed (HTTP=$reg_http)" >&2
    echo "$reg_raw" >&2
    exit 1
  fi

  local issue_raw issue_http mailbox_token
  issue_raw="$(curl -sS -w '\nHTTP:%{http_code}\n' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"device_id\":\"${device_id}\"}" \
    "${bff_url}/chat/mailboxes/issue")"
  issue_http="$(printf '%s' "$issue_raw" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  mailbox_token="$(printf '%s' "$issue_raw" | sed '/^HTTP:/d' | jq -r '.mailbox_token // empty')"
  if [[ "$issue_http" != "200" || -z "$mailbox_token" ]]; then
    echo "smoke-mailbox: issue failed (HTTP=$issue_http)" >&2
    echo "$issue_raw" >&2
    exit 1
  fi

  local write_http write_raw write_json write_id
  local replay_write_http replay_write_raw replay_write_id
  local poll_http poll_json poll_count poll_first_id
  local rotate_http rotate_json new_mailbox_token old_write_http
  local carry_http carry_poll_raw carry_poll_http carry_count carry_envelope carry_payload
  carry_payload="Y2FycnlfcGF5bG9hZF92MQ=="
  write_raw="$(curl -sS -w '\nHTTP:%{http_code}\n' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"mailbox_token\":\"${mailbox_token}\",\"envelope_b64\":\"${envelope}\",\"sender_hint\":\"smoke\"}" \
    "${bff_url}/chat/mailboxes/write")"
  write_http="$(printf '%s' "$write_raw" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  write_json="$(printf '%s' "$write_raw" | sed '/^HTTP:/d')"
  write_id="$(printf '%s' "$write_json" | jq -r '.id // empty')"
  if [[ "$write_http" != "200" || -z "$write_id" ]]; then
    echo "smoke-mailbox: write failed (HTTP=$write_http)" >&2
    echo "$write_raw" >&2
    exit 1
  fi

  replay_write_raw="$(curl -sS -w '\nHTTP:%{http_code}\n' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"mailbox_token\":\"${mailbox_token}\",\"envelope_b64\":\"${envelope}\",\"sender_hint\":\"smoke\"}" \
    "${bff_url}/chat/mailboxes/write")"
  replay_write_http="$(printf '%s' "$replay_write_raw" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  replay_write_id="$(printf '%s' "$replay_write_raw" | sed '/^HTTP:/d' | jq -r '.id // empty')"
  if [[ "$replay_write_http" != "200" || "$replay_write_id" != "$write_id" ]]; then
    echo "smoke-mailbox: replayed write did not dedupe idempotently (HTTP=$replay_write_http)" >&2
    echo "$replay_write_raw" >&2
    exit 1
  fi

  poll_json="$(curl -sS -w '\nHTTP:%{http_code}\n' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"device_id\":\"${device_id}\",\"mailbox_token\":\"${mailbox_token}\",\"limit\":10}" \
    "${bff_url}/chat/mailboxes/poll")"
  poll_http="$(printf '%s' "$poll_json" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  if [[ "$poll_http" != "200" ]]; then
    echo "smoke-mailbox: poll failed (HTTP=$poll_http)" >&2
    exit 1
  fi
  poll_count="$(printf '%s' "$poll_json" | sed '/^HTTP:/d' | jq 'length')"
  poll_first_id="$(printf '%s' "$poll_json" | sed '/^HTTP:/d' | jq -r '.[0].id // empty')"
  if [[ "$poll_count" != "1" || "$poll_first_id" != "$write_id" ]]; then
    echo "smoke-mailbox: replayed write produced duplicate mailbox rows." >&2
    echo "$poll_json" >&2
    exit 1
  fi

  carry_http="$(curl -sS -o /dev/null -w '%{http_code}' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"mailbox_token\":\"${mailbox_token}\",\"envelope_b64\":\"${carry_payload}\",\"sender_hint\":\"carry\"}" \
    "${bff_url}/chat/mailboxes/write")"
  if [[ "$carry_http" != "200" ]]; then
    echo "smoke-mailbox: carry write failed before rotate (HTTP=$carry_http)" >&2
    exit 1
  fi

  rotate_json="$(curl -sS -w '\nHTTP:%{http_code}\n' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"device_id\":\"${device_id}\",\"mailbox_token\":\"${mailbox_token}\"}" \
    "${bff_url}/chat/mailboxes/rotate")"
  rotate_http="$(printf '%s' "$rotate_json" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  new_mailbox_token="$(printf '%s' "$rotate_json" | sed '/^HTTP:/d' | jq -r '.mailbox_token // empty')"
  if [[ "$rotate_http" != "200" || -z "$new_mailbox_token" ]]; then
    echo "smoke-mailbox: rotate failed (HTTP=$rotate_http)" >&2
    echo "$rotate_json" >&2
    exit 1
  fi
  if [[ "$new_mailbox_token" == "$mailbox_token" ]]; then
    echo "smoke-mailbox: rotate returned same token (unexpected)." >&2
    exit 1
  fi

  carry_poll_raw="$(curl -sS -w '\nHTTP:%{http_code}\n' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"device_id\":\"${device_id}\",\"mailbox_token\":\"${new_mailbox_token}\",\"limit\":10}" \
    "${bff_url}/chat/mailboxes/poll")"
  carry_poll_http="$(printf '%s' "$carry_poll_raw" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  if [[ "$carry_poll_http" != "200" ]]; then
    echo "smoke-mailbox: post-rotate poll failed (HTTP=$carry_poll_http)" >&2
    exit 1
  fi
  carry_count="$(printf '%s' "$carry_poll_raw" | sed '/^HTTP:/d' | jq 'length')"
  carry_envelope="$(printf '%s' "$carry_poll_raw" | sed '/^HTTP:/d' | jq -r '.[0].envelope_b64 // empty')"
  if [[ "$carry_count" -lt 1 || "$carry_envelope" != "${carry_payload}" ]]; then
    echo "smoke-mailbox: rotated mailbox did not deliver pending backlog on new token." >&2
    echo "$carry_poll_raw" >&2
    exit 1
  fi

  old_write_http="$(curl -sS -o /dev/null -w '%{http_code}' "${common_headers[@]}" \
    -H "x-chat-device-id: ${device_id}" \
    -H "x-chat-device-token: ${auth_token}" \
    -d "{\"mailbox_token\":\"${mailbox_token}\",\"envelope_b64\":\"${envelope}\"}" \
    "${bff_url}/chat/mailboxes/write")"
  if [[ "$old_write_http" != "404" ]]; then
    echo "smoke-mailbox: old token write not rejected as 404 (HTTP=$old_write_http)" >&2
    exit 1
  fi

  echo "smoke-mailbox: ok (register=200 issue=200 write=200 replay_dedupe=200 poll=200 rotate=200 backlog_carry=200 old_write=404)"
}

smoke_payment_attestation() {
  require_cmd curl
  require_cmd jq
  require_cmd shasum
  require_cmd openssl

  local env_lower
  env_lower="$(read_env ENV | tr '[:upper:]' '[:lower:]')"
  if [[ -z "$env_lower" ]]; then
    env_lower="$(printf '%s' "$ENV_NAME" | tr '[:upper:]' '[:lower:]')"
  fi
  if [[ "$env_lower" == "prod" || "$env_lower" == "production" ]]; then
    if ! is_true_like "${SMOKE_ALLOW_PROD:-0}"; then
      echo "smoke-payment-attestation: refusing to write test rows in prod. Set SMOKE_ALLOW_PROD=1 to override." >&2
      exit 1
    fi
  fi

  local health_url base_url bff_port
  bff_port="$(read_env BFF_PUBLISH_PORT)"
  bff_port="${bff_port:-8080}"
  health_url="${HEALTH_URL:-$HEALTH_URL_DEFAULT}"
  base_url="${SMOKE_BASE_URL:-${SMOKE_BFF_URL:-}}"
  if [[ -z "$base_url" ]]; then
    if [[ "$health_url" == */health ]]; then
      base_url="${health_url%/health}"
    else
      base_url="$health_url"
    fi
  fi
  if [[ -z "$base_url" ]]; then
    base_url="http://127.0.0.1:${bff_port}"
  fi
  base_url="${base_url%/}"
  if [[ -z "$base_url" ]]; then
    echo "smoke-payment-attestation: could not derive SMOKE_BASE_URL." >&2
    exit 1
  fi

  local amount_cents
  amount_cents="${SMOKE_PAYMENT_AMOUNT_CENTS:-101}"
  if ! [[ "$amount_cents" =~ ^[1-9][0-9]*$ ]]; then
    echo "smoke-payment-attestation: SMOKE_PAYMENT_AMOUNT_CENTS must be a positive integer." >&2
    exit 1
  fi

  local expect_enabled
  expect_enabled="${SMOKE_EXPECT_PAYMENT_ATTESTATION_ENABLED:-}"
  if [[ -z "$expect_enabled" ]]; then
    expect_enabled="$(read_env AUTH_PAYMENT_MUTATION_HARDWARE_ATTESTATION_ENABLED)"
    if [[ -z "$expect_enabled" ]]; then
      expect_enabled="false"
    fi
  fi

  local pg_user pg_pass pg_core_db pg_payments_db
  pg_user="$(read_env POSTGRES_USER)"
  pg_pass="$(read_env POSTGRES_PASSWORD)"
  pg_core_db="$(read_env POSTGRES_DB_CORE)"
  pg_payments_db="$(read_env POSTGRES_DB_PAYMENTS)"
  pg_user="${pg_user:-shamell}"
  if [[ -z "$pg_pass" && "$ENV_NAME" == "dev" ]]; then
    pg_pass="shamell"
  fi
  pg_core_db="${pg_core_db:-shamell_core}"
  pg_payments_db="${pg_payments_db:-shamell_payments}"
  if [[ -z "$pg_pass" ]]; then
    echo "smoke-payment-attestation: missing POSTGRES_PASSWORD in env file." >&2
    exit 1
  fi

  local account_id shamell_user_id device_id sid sid_hash
  account_id="$(openssl rand -hex 32)"
  shamell_user_id="smk$(openssl rand -hex 6)"
  device_id="${SMOKE_DEVICE_ID:-pay-smk-$(openssl rand -hex 6)}"
  sid="$(openssl rand -hex 16)"
  sid_hash="$(printf '%s' "$sid" | shasum -a 256 | awk '{print $1}')"

  cleanup_smoke_payment_attestation() {
    local pg_user="${SMOKE_PAY_ATTEST_PG_USER:-}"
    local pg_pass="${SMOKE_PAY_ATTEST_PG_PASS:-}"
    local pg_core_db="${SMOKE_PAY_ATTEST_CORE_DB:-}"
    local pg_payments_db="${SMOKE_PAY_ATTEST_PAYMENTS_DB:-}"
    local sid_hash="${SMOKE_PAY_ATTEST_SID_HASH:-}"
    local account_id="${SMOKE_PAY_ATTEST_ACCOUNT_ID:-}"
    local device_id="${SMOKE_PAY_ATTEST_DEVICE_ID:-}"
    local wallet_id="${SMOKE_PAY_ATTEST_WALLET_ID:-}"
    if [[ -z "$pg_user" || -z "$pg_pass" || -z "$pg_core_db" || -z "$pg_payments_db" || -z "$sid_hash" || -z "$account_id" ]]; then
      return 0
    fi
    if [[ -n "$wallet_id" ]]; then
      compose exec -T db sh -lc "PGPASSWORD='${pg_pass}' psql -U '${pg_user}' -d '${pg_payments_db}' -v ON_ERROR_STOP=1 -q \
        -c \"DELETE FROM wallets WHERE id='${wallet_id}';\" \
        -c \"DELETE FROM users WHERE account_id='${account_id}';\"" >/dev/null 2>&1 || true
    fi
    compose exec -T db sh -lc "PGPASSWORD='${pg_pass}' psql -U '${pg_user}' -d '${pg_core_db}' -v ON_ERROR_STOP=1 -q \
      -c \"DELETE FROM auth_sessions WHERE sid_hash='${sid_hash}';\" \
      -c \"DELETE FROM device_sessions WHERE account_id='${account_id}' AND device_id='${device_id}';\" \
      -c \"DELETE FROM auth_accounts WHERE account_id='${account_id}';\"" >/dev/null 2>&1 || true
  }
  SMOKE_PAY_ATTEST_PG_USER="$pg_user"
  SMOKE_PAY_ATTEST_PG_PASS="$pg_pass"
  SMOKE_PAY_ATTEST_CORE_DB="$pg_core_db"
  SMOKE_PAY_ATTEST_PAYMENTS_DB="$pg_payments_db"
  SMOKE_PAY_ATTEST_SID_HASH="$sid_hash"
  SMOKE_PAY_ATTEST_ACCOUNT_ID="$account_id"
  SMOKE_PAY_ATTEST_DEVICE_ID="$device_id"
  SMOKE_PAY_ATTEST_WALLET_ID=""
  trap cleanup_smoke_payment_attestation EXIT

  compose exec -T db sh -lc "PGPASSWORD='${pg_pass}' psql -U '${pg_user}' -d '${pg_core_db}' -v ON_ERROR_STOP=1 -q" >/dev/null <<SQL
INSERT INTO auth_accounts (account_id, shamell_user_id, phone)
VALUES ('${account_id}', '${shamell_user_id}', NULL)
ON CONFLICT (account_id) DO UPDATE SET shamell_user_id=EXCLUDED.shamell_user_id;

INSERT INTO auth_sessions (sid_hash, account_id, phone, device_id, expires_at, created_at, last_seen_at, revoked_at)
VALUES ('${sid_hash}', '${account_id}', NULL, '${device_id}', NOW() + INTERVAL '1 day', NOW(), NOW(), NULL)
ON CONFLICT (sid_hash) DO UPDATE SET account_id=EXCLUDED.account_id, device_id=EXCLUDED.device_id, expires_at=EXCLUDED.expires_at, last_seen_at=NOW(), revoked_at=NULL;
SQL

  local curl_args=(-sS --connect-timeout 5 --max-time 20)
  if [[ "${SMOKE_INSECURE:-${HEALTH_INSECURE:-0}}" == "1" ]]; then
    curl_args+=(-k)
  fi
  local smoke_host="${SMOKE_HOST:-${HEALTH_HOST:-$HEALTH_HOST_DEFAULT}}"
  if [[ -n "$smoke_host" ]]; then
    curl_args+=(-H "Host: ${smoke_host}")
  fi
  if [[ -n "${SMOKE_RESOLVE:-${HEALTH_RESOLVE:-}}" ]]; then
    curl_args+=(--resolve "${SMOKE_RESOLVE:-$HEALTH_RESOLVE}")
  fi
  if [[ -n "${SMOKE_CLIENT_IP:-}" ]]; then
    curl_args+=(-H "X-Forwarded-For: ${SMOKE_CLIENT_IP}")
  fi

  json_get() {
    local raw="$1"
    local filter="$2"
    printf '%s' "$raw" | jq -r "$filter" 2>/dev/null || true
  }

  local wallet_id resource_id create_user_raw create_user_http create_user_json
  wallet_id=""
  if ! is_false_like "$expect_enabled"; then
    create_user_raw="$(curl "${curl_args[@]}" \
      -H "content-type: application/json" \
      -H "cookie: __Host-sa_session=${sid}" \
      -d '{}' \
      -w '\nHTTP:%{http_code}\n' \
      "${base_url}/payments/users")"
    create_user_http="$(printf '%s' "$create_user_raw" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
    create_user_json="$(printf '%s' "$create_user_raw" | sed '/^HTTP:/d')"
    wallet_id="$(json_get "$create_user_json" '.wallet_id // .id // empty')"
    if [[ "$create_user_http" != "200" || -z "$wallet_id" ]]; then
      echo "smoke-payment-attestation: payments/users provisioning failed (HTTP=$create_user_http)" >&2
      echo "$create_user_raw" >&2
      exit 1
    fi
    SMOKE_PAY_ATTEST_WALLET_ID="$wallet_id"
    resource_id="wallet_id=${wallet_id}&amount_cents=${amount_cents}"
  else
    resource_id="wallet_id=smoke-wallet&amount_cents=${amount_cents}"
  fi

  local challenge_raw challenge_http challenge_json challenge_enabled challenge_token nonce_b64 providers_csv providers_count
  challenge_raw="$(curl "${curl_args[@]}" \
    -H "content-type: application/json" \
    -H "cookie: __Host-sa_session=${sid}" \
    -d "{\"device_id\":\"${device_id}\",\"operation\":\"payments_topup\",\"resource_id\":\"${resource_id}\"}" \
    -w '\nHTTP:%{http_code}\n' \
    "${base_url}/auth/payment_attestation/challenge")"
  challenge_http="$(printf '%s' "$challenge_raw" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  challenge_json="$(printf '%s' "$challenge_raw" | sed '/^HTTP:/d')"
  challenge_enabled="$(json_get "$challenge_json" '.enabled // false')"
  challenge_token="$(json_get "$challenge_json" '.challenge_token // empty')"
  nonce_b64="$(json_get "$challenge_json" '.hw_attestation_nonce_b64 // empty')"
  providers_csv="$(json_get "$challenge_json" '(.hw_attestation_providers // []) | map(tostring) | join(",")')"
  providers_count="$(json_get "$challenge_json" '(.hw_attestation_providers // []) | length')"
  if [[ "$challenge_http" != "200" ]]; then
    echo "smoke-payment-attestation: challenge failed (HTTP=$challenge_http)" >&2
    echo "$challenge_raw" >&2
    exit 1
  fi

  if is_false_like "$expect_enabled"; then
    if [[ "$challenge_enabled" != "false" ]]; then
      echo "smoke-payment-attestation: expected enabled=false, got enabled=$challenge_enabled" >&2
      echo "$challenge_raw" >&2
      exit 1
    fi
    echo "smoke-payment-attestation: ok (enabled=false challenge=200)"
    return 0
  fi

  if [[ "$challenge_enabled" != "true" || -z "$challenge_token" || -z "$nonce_b64" || -z "$providers_count" || "$providers_count" == "0" ]]; then
    echo "smoke-payment-attestation: challenge response missing enabled token/nonce/providers." >&2
    echo "$challenge_raw" >&2
    exit 1
  fi

  local reject_raw reject_http reject_json reject_detail
  reject_raw="$(curl "${curl_args[@]}" \
    -H "content-type: application/json" \
    -H "cookie: __Host-sa_session=${sid}" \
    -H "x-device-id: ${device_id}" \
    -H "x-shamell-payment-attestation-challenge: ${challenge_token}" \
    -d "{\"amount_cents\":${amount_cents}}" \
    -w '\nHTTP:%{http_code}\n' \
    "${base_url}/payments/wallets/${wallet_id}/topup")"
  reject_http="$(printf '%s' "$reject_raw" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
  reject_json="$(printf '%s' "$reject_raw" | sed '/^HTTP:/d')"
  reject_detail="$(json_get "$reject_json" '.detail // empty')"
  if [[ "$reject_http" != "401" ]] || ! printf '%s' "$reject_detail" | grep -qi 'attestation required'; then
    echo "smoke-payment-attestation: expected topup without hardware token to fail closed with 401 attestation required (HTTP=$reject_http)." >&2
    echo "$reject_raw" >&2
    exit 1
  fi

  echo "smoke-payment-attestation: ok (enabled=true providers=${providers_csv} challenge=200 topup_without_hw_token=401)"
}

smoke_api() {
  require_cmd curl

  # Keep this read-only and low-noise: it should be safe to run in prod.
  local health_url base_url
  health_url="${HEALTH_URL:-$HEALTH_URL_DEFAULT}"
  base_url="${SMOKE_BASE_URL:-}"
  if [[ -z "$base_url" ]]; then
    # Derive from health URL. If the health URL ends with /health, strip it.
    if [[ "$health_url" == */health ]]; then
      base_url="${health_url%/health}"
    else
      base_url="$health_url"
    fi
  fi
  base_url="${base_url%/}"
  if [[ -z "$base_url" ]]; then
    echo "smoke-api: could not derive SMOKE_BASE_URL." >&2
    exit 1
  fi

  local curl_args=(-sS)
  if [[ "${SMOKE_INSECURE:-${HEALTH_INSECURE:-0}}" == "1" ]]; then
    curl_args+=(-k)
  fi
  local smoke_host="${SMOKE_HOST:-${HEALTH_HOST:-$HEALTH_HOST_DEFAULT}}"
  if [[ -n "$smoke_host" ]]; then
    curl_args+=(-H "Host: ${smoke_host}")
  fi
  if [[ -n "${SMOKE_RESOLVE:-${HEALTH_RESOLVE:-}}" ]]; then
    curl_args+=(--resolve "${SMOKE_RESOLVE:-$HEALTH_RESOLVE}")
  fi
  if [[ -n "${SMOKE_CLIENT_IP:-}" ]]; then
    curl_args+=(-H "X-Forwarded-For: ${SMOKE_CLIENT_IP}")
  fi

  local tmp status body url
  tmp="$(mktemp)"
  local health_status me_roles_status chat_inbox_status internal_alerts_status
  local legacy_account_create_challenge_status

  request() {
    local method="$1"
    url="$2"
    shift 2
    status="$(
      curl "${curl_args[@]}" \
        --connect-timeout 5 \
        --max-time 12 \
        -X "$method" \
        "$@" \
        -o "$tmp" \
        -w "%{http_code}" \
        "$url"
    )"
    body="$(cat "$tmp" || true)"
  }

  fail_if_internal_auth_error() {
    local name="$1"
    local status="$2"
    local body="$3"
    if echo "$body" | grep -qi "internal auth required"; then
      echo "smoke-api: FAIL ($name) returned internal auth required (HTTP=$status)." >&2
      exit 1
    fi
    if echo "$body" | grep -qi "internal auth not configured"; then
      echo "smoke-api: FAIL ($name) internal auth not configured (HTTP=$status)." >&2
      exit 1
    fi
  }

  # 1) Health must be OK (fast fail).
  request GET "${base_url}/health"
  health_status="$status"
  if [[ "$status" != "200" ]]; then
    echo "smoke-api: FAIL health check (${base_url}/health) (HTTP=$status)." >&2
    rm -f "$tmp"
    exit 1
  fi

  # 2) Public authed routes must NOT require X-Internal-Secret.
  request GET "${base_url}/me/roles"
  me_roles_status="$status"
  fail_if_internal_auth_error "me/roles" "$status" "$body"
  if [[ "$status" != "401" && "$status" != "403" ]]; then
    echo "smoke-api: FAIL me/roles expected 401/403 without session (HTTP=$status)." >&2
    rm -f "$tmp"
    exit 1
  fi

  # 3) Chat routes must also fail with normal auth errors (not internal-auth),
  # and must not reach upstream without a session.
  request GET "${base_url}/chat/messages/inbox?device_id=smoke_device"
  chat_inbox_status="$status"
  fail_if_internal_auth_error "chat/messages/inbox" "$status" "$body"
  if [[ "$status" != "401" && "$status" != "403" ]]; then
    echo "smoke-api: FAIL chat inbox expected 401/403 without session (HTTP=$status)." >&2
    rm -f "$tmp"
    exit 1
  fi

  # 4) Internal-only route must remain non-public (Nginx blocks /internal/*),
  # or (direct BFF) must require X-Internal-Secret.
  request POST "${base_url}/internal/security/alerts" -H "content-type: application/json" -d "{}"
  internal_alerts_status="$status"
  if [[ "$status" == "200" || "$status" == "201" || "$status" == "202" ]]; then
    echo "smoke-api: FAIL internal/security/alerts unexpectedly accepted request (HTTP=$status)." >&2
    rm -f "$tmp"
    exit 1
  fi
  # Accept 401 (internal-auth), 403/404 (edge block), 405 (method mismatch).
  if [[ "$status" != "401" && "$status" != "403" && "$status" != "404" && "$status" != "405" ]]; then
    echo "smoke-api: FAIL internal/security/alerts unexpected status (HTTP=$status)." >&2
    rm -f "$tmp"
    exit 1
  fi

  # 5) Legacy passwordless account-create challenge must remain retired. The
  # current public signup route is /auth/signup; smoke-api stays read-only.
  request POST "${base_url}/auth/account/create/challenge" \
    -H "content-type: application/json" \
    -d '{"device_id":"smoke_device"}'
  legacy_account_create_challenge_status="$status"
  fail_if_internal_auth_error "auth/account/create/challenge" "$status" "$body"
  if [[ "$status" != "410" ]]; then
    echo "smoke-api: FAIL legacy account-create challenge expected 410 (HTTP=$status)." >&2
    rm -f "$tmp"
    exit 1
  fi

  rm -f "$tmp"
  echo "smoke-api: ok (base=${base_url} health=${health_status} me_roles=${me_roles_status} chat_inbox=${chat_inbox_status} internal_alerts=${internal_alerts_status} legacy_account_create_challenge=${legacy_account_create_challenge_status})"
}

smoke_payments_moneyflow() {
  if [[ "$ENV_NAME" == "dev" ]]; then
    echo "smoke-payments-moneyflow: run against pipg/prod env." >&2
    exit 1
  fi

  local script_path="${APP_DIR}/scripts/smoke_payments_moneyflow.sh"
  if [[ ! -x "$script_path" ]]; then
    echo "smoke-payments-moneyflow: script missing or not executable: ${script_path}" >&2
    exit 1
  fi

  COMPOSE_FILE="$COMPOSE_FILE" ENV_FILE="$ENV_FILE_PATH" "$script_path"
}

smoke_ride_flow() {
  if [[ "$ENV_NAME" != "dev" ]]; then
    echo "smoke-ride-flow: run against dev env." >&2
    exit 1
  fi

  local script_path="${APP_DIR}/scripts/e2e_ride_flow.sh"
  if [[ ! -x "$script_path" ]]; then
    echo "smoke-ride-flow: script missing or not executable: ${script_path}" >&2
    exit 1
  fi

  "$script_path" "$@"
}

ride_report() {
  local script_path="${APP_DIR}/scripts/ride_ops_report.sh"
  if [[ ! -x "$script_path" ]]; then
    echo "ride-report: script missing or not executable: ${script_path}" >&2
    exit 1
  fi

  COMPOSE_FILE="$COMPOSE_FILE" ENV_FILE="$ENV_FILE_PATH" bash "$script_path" "$@"
}

ride_repair_stale_presence() {
  if [[ "$ENV_NAME" == "dev" ]]; then
    echo "ride-repair-stale-presence: run against pipg/prod env." >&2
    exit 1
  fi

  local script_path="${APP_DIR}/scripts/repair_ride_stale_presence.sh"
  if [[ ! -x "$script_path" ]]; then
    echo "ride-repair-stale-presence: script missing or not executable: ${script_path}" >&2
    exit 1
  fi

  COMPOSE_FILE="$COMPOSE_FILE" ENV_FILE="$ENV_FILE_PATH" bash "$script_path" "$@"
}

ride_release_gate() {
  if [[ "$ENV_NAME" == "dev" ]]; then
    smoke_ride_flow "$@"
    return 0
  fi

  check_env

  if ! is_true_like "${RIDE_RELEASE_GATE_SKIP_SCHEMA_MIGRATE:-0}"; then
    schema_migrate bff
    schema_migrate payments
  fi

  if [[ -z "${HEALTH_RETRIES:-}" ]]; then
    HEALTH_RETRIES=10
  fi
  if [[ -z "${HEALTH_RETRY_DELAY:-}" ]]; then
    HEALTH_RETRY_DELAY=2
  fi
  health
  smoke_api
  RIDE_REPORT_FAIL_ON_FINDINGS=1 ride_report

  if is_true_like "${RIDE_RELEASE_GATE_RUN_MATRIX_API:-0}"; then
    matrix_api
  fi
}

matrix_api() {
  if [[ "$ENV_NAME" == "dev" ]]; then
    echo "matrix-api: run against pipg/prod env." >&2
    exit 1
  fi

  local script_path="${APP_DIR}/scripts/pipg_api_matrix.sh"
  if [[ ! -x "$script_path" ]]; then
    echo "matrix-api: script missing or not executable: ${script_path}" >&2
    exit 1
  fi

  COMPOSE_FILE="$COMPOSE_FILE" ENV_FILE="$ENV_FILE_PATH" "$script_path" "$@"
}

case "$CMD" in
  up)
    compose_up_with_build_fallback "Up" "$@"
    ;;
  down)
    compose down "$@"
    ;;
  restart)
    compose restart "$@"
    ;;
  logs)
    if [[ "$#" -eq 0 ]]; then
      compose logs -f --tail=200
    else
      compose logs "$@"
    fi
    ;;
  ps|status)
    compose ps
    ;;
  report)
    report
    ;;
  cloudflare-status|cloudflare_status|status-cloudflare)
    cloudflare_status "$@"
    ;;
  cloudflare-refresh|cloudflare_refresh|refresh-cloudflare)
    cloudflare_refresh "$@"
    ;;
  sync-nginx|sync_nginx|nginx-sync)
    sync_nginx "$@"
    ;;
  sync-ufw|sync_ufw|ufw-sync)
    sync_ufw "$@"
    ;;
  sync-edge|sync_edge|edge-sync)
    sync_edge "$@"
    ;;
  smoke-api|smoke_api|api-smoke)
    smoke_api
    ;;
  smoke-mailbox|smoke_mailbox|mailbox-smoke)
    smoke_mailbox
    ;;
  smoke-payment-attestation|smoke_payment_attestation|payment-attestation-smoke)
    smoke_payment_attestation
    ;;
  smoke-payments-moneyflow|smoke_payments_moneyflow|payments-moneyflow-smoke)
    smoke_payments_moneyflow
    ;;
  smoke-ride-flow|smoke_ride_flow|ride-flow-smoke)
    smoke_ride_flow "$@"
    ;;
  ride-report|ride_report|ride-ops-report)
    ride_report "$@"
    ;;
  ride-repair-stale-presence|ride_repair_stale_presence|ride-presence-repair)
    ride_repair_stale_presence "$@"
    ;;
  ride-release-gate|ride_release_gate|ride-gate)
    ride_release_gate "$@"
    ;;
  schema-migrate|schema_migrate|schema-migrations)
    schema_migrate "$@"
    ;;
  sync-ride-report-timer|sync_ride_report_timer|ride-report-timer-sync)
    sync_ride_report_timer "$@"
    ;;
  matrix-api|matrix_api|api-matrix)
    matrix_api "$@"
    ;;
  security-report|security_alerts)
    security_report "$@"
    ;;
  security-drill|security_webhook_drill)
    security_drill "$@"
    ;;
  access-assign|access_assign|access-assignment)
    access_assign "$@"
    ;;
  build)
    compose_build_with_fallback "Build" "$@"
    ;;
  pull)
    compose pull "$@"
    ;;
  health)
    health
    ;;
  check)
    check_env
    ;;
  deploy)
    deploy "$@"
    ;;
  migrate)
    migrate
    ;;
  backup)
    backup
    ;;
  restore)
    restore "$@"
    ;;
  shell)
    compose exec "$PRIMARY_SERVICE" sh
    ;;
  *)
    usage
    exit 1
    ;;
esac
