#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib_internal_identity.sh"
COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/ops/pi/docker-compose.postgres.yml}"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/ops/pi/.env}"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "pipg_api_matrix: missing required command: $cmd" >&2
    exit 1
  fi
}

read_env() {
  local key="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    return 0
  fi
  awk -F= -v k="$key" '$1==k{v=substr($0, index($0,$2))} END{print v}' "$ENV_FILE"
}

compose() {
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

matches_expected() {
  local actual="$1"
  local expected_csv="$2"
  local item
  IFS=',' read -r -a _expected <<<"$expected_csv"
  for item in "${_expected[@]}"; do
    item="${item//[[:space:]]/}"
    if [[ -n "$item" && "$actual" == "$item" ]]; then
      return 0
    fi
  done
  return 1
}

http_code() {
  local method="$1"
  local route="$2"
  local body="$3"
  shift 3 || true
  local -a headers=("$@")
  local -a args=(-sS -o /dev/null -w '%{http_code}' -X "$method")
  if (( ${#MATRIX_BASE_HEADERS[@]} > 0 )); then
    args+=("${MATRIX_BASE_HEADERS[@]}")
  fi
  if (( ${#headers[@]} > 0 )); then
    args+=("${headers[@]}")
  fi
  if [[ -n "$body" ]]; then
    args+=(-H "content-type: application/json" -d "$body")
  fi
  args+=("${BASE_URL}${route}")
  curl "${args[@]}"
}

require_cmd docker
require_cmd curl
require_cmd jq
require_cmd openssl
require_cmd shasum
require_cmd awk

if [[ ! -f "$ENV_FILE" ]]; then
  echo "pipg_api_matrix: env file not found: $ENV_FILE" >&2
  exit 1
fi

BFF_PORT="$(read_env BFF_PUBLISH_PORT)"
BFF_PORT="${BFF_PORT:-8080}"
BFF_ADDR="$(read_env BFF_PUBLISH_ADDR)"
BFF_ADDR="${BFF_ADDR:-127.0.0.1}"
if [[ "$BFF_ADDR" == "0.0.0.0" ]]; then
  BFF_ADDR="127.0.0.1"
fi

BASE_URL="${MATRIX_BASE_URL:-http://${BFF_ADDR}:${BFF_PORT}}"
MATRIX_HOST="${MATRIX_HOST:-bff}"
MATRIX_BASE_HEADERS=()
if [[ -n "$MATRIX_HOST" ]]; then
  MATRIX_BASE_HEADERS=(-H "Host: ${MATRIX_HOST}")
fi
INTERNAL_SECRET="$(read_env INTERNAL_API_SECRET)"
CALLER="${MATRIX_INTERNAL_CALLER:-edge}"
CALLER="$(internal_identity_normalize_service_id "$CALLER")"
CLIENT_IP="${MATRIX_CLIENT_IP:-203.0.113.10}"

PG_USER="$(read_env POSTGRES_USER)"
PG_USER="${PG_USER:-shamell}"
PG_PASS="$(read_env POSTGRES_PASSWORD)"
PG_DB_CORE="$(read_env POSTGRES_DB_CORE)"
PG_DB_CORE="${PG_DB_CORE:-shamell_core}"

if [[ -z "$INTERNAL_SECRET" ]]; then
  echo "pipg_api_matrix: missing INTERNAL_API_SECRET in $ENV_FILE" >&2
  exit 1
fi
if [[ -z "$PG_PASS" ]]; then
  echo "pipg_api_matrix: missing POSTGRES_PASSWORD in $ENV_FILE" >&2
  exit 1
fi

ACCOUNT_ID="$(openssl rand -hex 32)"
SHAMELL_USER_ID="mx$(openssl rand -hex 6)"
PHONE="${MATRIX_PHONE:-+1555555$(date +%H%M%S)}"
DEVICE_ID="${MATRIX_DEVICE_ID:-mx$(date +%s | tail -c 7)}"
SID="$(openssl rand -hex 16)"
SID_HASH="$(printf '%s' "$SID" | shasum -a 256 | awk '{print $1}')"
PUB_KEY_B64="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123456789AB"

cleanup() {
  compose exec -T db sh -lc "PGPASSWORD='${PG_PASS}' psql -U '${PG_USER}' -d '${PG_DB_CORE}' -v ON_ERROR_STOP=1 -q \
    -c \"DELETE FROM auth_sessions WHERE sid_hash='${SID_HASH}';\" \
    -c \"DELETE FROM device_sessions WHERE account_id='${ACCOUNT_ID}' AND device_id='${DEVICE_ID}';\" \
    -c \"DELETE FROM auth_accounts WHERE account_id='${ACCOUNT_ID}';\"" >/dev/null 2>&1 || true
}
trap cleanup EXIT

compose exec -T db sh -lc "PGPASSWORD='${PG_PASS}' psql -U '${PG_USER}' -d '${PG_DB_CORE}' -v ON_ERROR_STOP=1 -q" >/dev/null <<SQL
INSERT INTO auth_accounts (account_id, shamell_user_id, phone)
VALUES ('${ACCOUNT_ID}', '${SHAMELL_USER_ID}', '${PHONE}')
ON CONFLICT (account_id) DO UPDATE SET shamell_user_id=EXCLUDED.shamell_user_id, phone=EXCLUDED.phone;

INSERT INTO auth_sessions (sid_hash, account_id, phone, device_id, expires_at, created_at, last_seen_at, revoked_at)
VALUES ('${SID_HASH}', '${ACCOUNT_ID}', '${PHONE}', '${DEVICE_ID}', NOW() + INTERVAL '1 day', NOW(), NOW(), NULL)
ON CONFLICT (sid_hash) DO UPDATE SET account_id=EXCLUDED.account_id, phone=EXCLUDED.phone, device_id=EXCLUDED.device_id, expires_at=EXCLUDED.expires_at, last_seen_at=NOW(), revoked_at=NULL;

INSERT INTO device_sessions (account_id, phone, device_id, device_type, device_name, platform, app_version, last_ip, user_agent, created_at, last_seen_at)
VALUES ('${ACCOUNT_ID}', '${PHONE}', '${DEVICE_ID}', 'mobile', 'matrix', 'ios', '1.0', '${CLIENT_IP}', 'pipg_api_matrix', NOW(), NOW())
ON CONFLICT (account_id, device_id) DO UPDATE SET phone=EXCLUDED.phone, last_seen_at=NOW(), last_ip=EXCLUDED.last_ip, user_agent=EXCLUDED.user_agent;
SQL

REG_RAW="$(curl -sS -w '\nHTTP:%{http_code}\n' \
  "${MATRIX_BASE_HEADERS[@]}" \
  -H "x-internal-secret: ${INTERNAL_SECRET}" \
  -H "x-internal-service-id: ${CALLER}" \
  -H "x-forwarded-for: ${CLIENT_IP}" \
  -H "content-type: application/json" \
  -H "cookie: __Host-sa_session=${SID}" \
  -d "{\"device_id\":\"${DEVICE_ID}\",\"public_key_b64\":\"${PUB_KEY_B64}\",\"name\":\"pipg_matrix\"}" \
  "${BASE_URL}/chat/devices/register")"
REG_HTTP="$(printf '%s' "$REG_RAW" | awk -F: '/^HTTP:/{print $2}' | tail -n1)"
AUTH_TOKEN="$(printf '%s' "$REG_RAW" | sed '/^HTTP:/d' | jq -r '.auth_token // empty')"

if [[ "$REG_HTTP" != "200" || -z "$AUTH_TOKEN" ]]; then
  echo "pipg_api_matrix: chat register failed (HTTP=$REG_HTTP)" >&2
  echo "$REG_RAW" >&2
  exit 1
fi

COMMON_AUTH_HEADERS=(
  -H "x-internal-secret: ${INTERNAL_SECRET}"
  -H "x-internal-service-id: ${CALLER}"
  -H "x-forwarded-for: ${CLIENT_IP}"
  -H "cookie: __Host-sa_session=${SID}"
)

CHAT_AUTH_HEADERS=(
  "${COMMON_AUTH_HEADERS[@]}"
  -H "x-chat-device-id: ${DEVICE_ID}"
  -H "x-chat-device-token: ${AUTH_TOKEN}"
)

matrix_rows=(
  "official.list|GET|/official_accounts||normal|401|200"
  "official.notifications|GET|/official_accounts/notifications||normal|401|200"
  "official.auto_replies|GET|/official_accounts/shamell_pay/auto_replies||normal|401|200"
  "official.follow|POST|/official_accounts/shamell_pay/follow|{}|normal|401|200"
  "official.unfollow|POST|/official_accounts/shamell_pay/unfollow|{}|normal|401|200"
  "official.admin.owners|GET|/admin/official_accounts/shamell_pay/owners||normal|401|403"
  "official.admin.auto_replies|GET|/admin/official_accounts/shamell_pay/auto_replies||normal|401|403"
  "official.admin.service_inbox|GET|/admin/official_accounts/shamell_pay/service_inbox||normal|401|403"
  "chat.mailbox_issue|POST|/chat/mailboxes/issue|{\"device_id\":\"__DEVICE__\"}|chat|401|200"
  "chat.device_get|GET|/chat/devices/__DEVICE__||chat|401|200"
  "auth.me_roles|GET|/me/roles||normal|401|200"
  "admin.roles|GET|/admin/roles||normal|401|403"
  "payments.wallet|GET|/payments/wallets/test_wallet||normal|401|403,404,409"
)

total=0
failed=0

echo "pipg_api_matrix: base=${BASE_URL}"
echo "pipg_api_matrix: device_id=${DEVICE_ID}"
printf '%-30s %-5s %-46s %-17s %-17s %s\n' "key" "verb" "route" "unauth" "auth" "result"

for row in "${matrix_rows[@]}"; do
  IFS='|' read -r key method route body auth_mode exp_unauth exp_auth <<<"$row"

  route="${route//__DEVICE__/${DEVICE_ID}}"
  body="${body//__DEVICE__/${DEVICE_ID}}"

  unauth_code="$(http_code "$method" "$route" "$body")"

  if [[ "$auth_mode" == "chat" ]]; then
    auth_code="$(http_code "$method" "$route" "$body" "${CHAT_AUTH_HEADERS[@]}")"
  else
    auth_code="$(http_code "$method" "$route" "$body" "${COMMON_AUTH_HEADERS[@]}")"
  fi

  result="PASS"
  if ! matches_expected "$unauth_code" "$exp_unauth"; then
    result="FAIL"
  fi
  if ! matches_expected "$auth_code" "$exp_auth"; then
    result="FAIL"
  fi

  printf '%-30s %-5s %-46s u=%-3s exp=%-7s a=%-3s exp=%-7s %s\n' \
    "$key" "$method" "$route" "$unauth_code" "$exp_unauth" "$auth_code" "$exp_auth" "$result"

  total=$((total + 1))
  if [[ "$result" != "PASS" ]]; then
    failed=$((failed + 1))
  fi
done

passed=$((total - failed))
echo "pipg_api_matrix: summary total=${total} passed=${passed} failed=${failed}"

if (( failed > 0 )); then
  exit 1
fi
