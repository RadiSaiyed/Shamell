#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib_internal_identity.sh"

COMPOSE_FILE="${COMPOSE_FILE:-${ROOT_DIR}/ops/pi/docker-compose.postgres.yml}"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/ops/pi/.env}"

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "smoke-payments-moneyflow: missing required command: ${cmd}" >&2
    exit 1
  }
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

is_true_like() {
  local v
  v="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "on" || "$v" == "yes" ]]
}

http_code_from_raw() {
  local raw="$1"
  printf '%s' "$raw" | awk -F: '/^HTTP:/{print $2}' | tail -n1
}

http_body_from_raw() {
  local raw="$1"
  printf '%s' "$raw" | sed '/^HTTP:/d'
}

assert_status() {
  local label="$1"
  local raw="$2"
  local expected_csv="$3"
  local code
  code="$(http_code_from_raw "$raw")"
  local expected item
  IFS=',' read -r -a expected <<<"$expected_csv"
  for item in "${expected[@]}"; do
    item="${item//[[:space:]]/}"
    if [[ -n "$item" && "$code" == "$item" ]]; then
      return 0
    fi
  done
  echo "smoke-payments-moneyflow: ${label} failed (HTTP=${code}, expected=${expected_csv})" >&2
  echo "$(http_body_from_raw "$raw")" >&2
  exit 1
}

signed_payments_call() {
  local method="$1"
  local path="$2"
  local body_json="$3"
  shift 3 || true
  local -a extra_headers=()
  if (($# > 0)); then
    extra_headers=("$@")
  fi

  local tmp_body
  tmp_body="$(mktemp)"
  printf '%s' "$body_json" >"$tmp_body"

  local url="http://payments:8082${path}"
  local signed_headers
  signed_headers="$(
    internal_identity_build_curl_headers \
      "$BFF_SIGNING_SEED_B64" \
      "bff" \
      "payments" \
      "$method" \
      "$url" \
      "$tmp_body"
  )"

  local -a signed_header_args=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    signed_header_args+=(-H "$line")
  done <<<"$signed_headers"

  local -a curl_args=(-sS -w '\nHTTP:%{http_code}\n' -X "$method")
  curl_args+=("${signed_header_args[@]}")
  if ((${#extra_headers[@]} > 0)); then
    curl_args+=("${extra_headers[@]}")
  fi

  local out
  if [[ -n "$body_json" ]]; then
    curl_args+=(-H "content-type: application/json" --data-binary @- "$url")
    out="$(compose exec -T bff curl "${curl_args[@]}" <"$tmp_body")"
  else
    curl_args+=("$url")
    out="$(compose exec -T bff curl "${curl_args[@]}")"
  fi
  rm -f "$tmp_body"
  printf '%s' "$out"
}

require_cmd docker
require_cmd curl
require_cmd jq
require_cmd openssl
require_cmd awk

if [[ ! -f "$ENV_FILE" ]]; then
  echo "smoke-payments-moneyflow: env file not found: ${ENV_FILE}" >&2
  exit 1
fi

runtime_env="$(printf '%s' "$(read_env ENV)" | tr '[:upper:]' '[:lower:]')"
if [[ "$runtime_env" == "prod" || "$runtime_env" == "production" ]]; then
  if ! is_true_like "${SMOKE_ALLOW_PROD:-0}"; then
    echo "smoke-payments-moneyflow: refusing to write test rows in prod. Set SMOKE_ALLOW_PROD=1 to override." >&2
    exit 1
  fi
fi

BFF_SIGNING_SEED_B64="$(read_env BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64)"
if [[ -z "$BFF_SIGNING_SEED_B64" ]]; then
  echo "smoke-payments-moneyflow: missing BFF_INTERNAL_IDENTITY_SIGNING_SEED_B64 in ${ENV_FILE}" >&2
  exit 1
fi

topup_amount_cents="${SMOKE_MONEYFLOW_TOPUP_CENTS:-5000}"
transfer_amount_cents="${SMOKE_MONEYFLOW_TRANSFER_CENTS:-1200}"
request_amount_cents="${SMOKE_MONEYFLOW_REQUEST_CENTS:-333}"
if ! [[ "$topup_amount_cents" =~ ^[1-9][0-9]*$ ]]; then
  echo "smoke-payments-moneyflow: SMOKE_MONEYFLOW_TOPUP_CENTS must be a positive integer." >&2
  exit 1
fi
if ! [[ "$transfer_amount_cents" =~ ^[1-9][0-9]*$ ]]; then
  echo "smoke-payments-moneyflow: SMOKE_MONEYFLOW_TRANSFER_CENTS must be a positive integer." >&2
  exit 1
fi
if ! [[ "$request_amount_cents" =~ ^[1-9][0-9]*$ ]]; then
  echo "smoke-payments-moneyflow: SMOKE_MONEYFLOW_REQUEST_CENTS must be a positive integer." >&2
  exit 1
fi

acc_a="$(openssl rand -hex 32)"
acc_b="$(openssl rand -hex 32)"

ikey_user_a="smk-user-a-$(openssl rand -hex 4)"
ikey_user_b="smk-user-b-$(openssl rand -hex 4)"
ikey_topup="smk-topup-$(openssl rand -hex 4)"
ikey_transfer="smk-transfer-$(openssl rand -hex 4)"
ikey_request_accept="smk-request-accept-$(openssl rand -hex 4)"
ikey_request_cancel="smk-request-cancel-$(openssl rand -hex 4)"
ikey_favorite_create="smk-favorite-create-$(openssl rand -hex 4)"
ikey_favorite_delete="smk-favorite-delete-$(openssl rand -hex 4)"

raw="$(
  signed_payments_call \
    POST \
    "/users" \
    "{\"account_id\":\"${acc_a}\"}" \
    -H "Idempotency-Key: ${ikey_user_a}"
)"
assert_status "create_user_a" "$raw" "200"
wallet_a="$(http_body_from_raw "$raw" | jq -r '.wallet_id // empty')"
if [[ -z "$wallet_a" ]]; then
  echo "smoke-payments-moneyflow: create_user_a missing wallet_id" >&2
  echo "$(http_body_from_raw "$raw")" >&2
  exit 1
fi

raw="$(
  signed_payments_call \
    POST \
    "/users" \
    "{\"account_id\":\"${acc_b}\"}" \
    -H "Idempotency-Key: ${ikey_user_b}"
)"
assert_status "create_user_b" "$raw" "200"
wallet_b="$(http_body_from_raw "$raw" | jq -r '.wallet_id // empty')"
if [[ -z "$wallet_b" ]]; then
  echo "smoke-payments-moneyflow: create_user_b missing wallet_id" >&2
  echo "$(http_body_from_raw "$raw")" >&2
  exit 1
fi

raw="$(
  signed_payments_call \
    POST \
    "/wallets/${wallet_a}/topup" \
    "{\"amount_cents\":${topup_amount_cents}}" \
    -H "Idempotency-Key: ${ikey_topup}"
)"
topup_http="$(http_code_from_raw "$raw")"
if [[ "$topup_http" == "403" ]] && [[ "$(http_body_from_raw "$raw")" == *"Topup disabled"* ]]; then
  echo "smoke-payments-moneyflow: topup is disabled (403 Topup disabled)." >&2
  echo "Set PAYMENTS_EMERGENCY_DIRECT_TOPUP_ENABLED=true (or enable direct topup in non-prod) before running this full moneyflow smoke." >&2
  exit 1
fi
assert_status "topup" "$raw" "200"

raw="$(
  signed_payments_call \
    POST \
    "/wallets/${wallet_a}/topup" \
    "{\"amount_cents\":${topup_amount_cents}}" \
    -H "Idempotency-Key: ${ikey_topup}"
)"
assert_status "topup_replay" "$raw" "200"

raw="$(
  signed_payments_call \
    POST \
    "/transfer" \
    "{\"from_wallet_id\":\"${wallet_a}\",\"to_wallet_id\":\"${wallet_b}\",\"amount_cents\":${transfer_amount_cents}}" \
    -H "Idempotency-Key: ${ikey_transfer}"
)"
assert_status "transfer" "$raw" "200"

raw="$(
  signed_payments_call \
    POST \
    "/transfer" \
    "{\"from_wallet_id\":\"${wallet_a}\",\"to_wallet_id\":\"${wallet_b}\",\"amount_cents\":${transfer_amount_cents}}" \
    -H "Idempotency-Key: ${ikey_transfer}"
)"
assert_status "transfer_replay" "$raw" "200"

raw="$(
  signed_payments_call \
    POST \
    "/requests" \
    "{\"from_wallet_id\":\"${wallet_a}\",\"to_wallet_id\":\"${wallet_b}\",\"amount_cents\":${request_amount_cents},\"message\":\"smoke accept\"}" \
    -H "Idempotency-Key: ${ikey_request_accept}"
)"
assert_status "request_create_accept_path" "$raw" "200"
request_accept_id="$(http_body_from_raw "$raw" | jq -r '.id // empty')"
if [[ -z "$request_accept_id" ]]; then
  echo "smoke-payments-moneyflow: request_create_accept_path missing id" >&2
  echo "$(http_body_from_raw "$raw")" >&2
  exit 1
fi

raw="$(signed_payments_call GET "/requests?wallet_id=${wallet_a}" "")"
assert_status "requests_list" "$raw" "200"

raw="$(
  signed_payments_call \
    POST \
    "/requests/${request_accept_id}/accept" \
    "{\"to_wallet_id\":\"${wallet_b}\"}" \
    -H "Idempotency-Key: smk-request-accept-final-$(openssl rand -hex 4)"
)"
assert_status "request_accept" "$raw" "200"

raw="$(
  signed_payments_call \
    POST \
    "/requests" \
    "{\"from_wallet_id\":\"${wallet_a}\",\"to_wallet_id\":\"${wallet_b}\",\"amount_cents\":${request_amount_cents},\"message\":\"smoke cancel\"}" \
    -H "Idempotency-Key: ${ikey_request_cancel}"
)"
assert_status "request_create_cancel_path" "$raw" "200"
request_cancel_id="$(http_body_from_raw "$raw" | jq -r '.id // empty')"
if [[ -z "$request_cancel_id" ]]; then
  echo "smoke-payments-moneyflow: request_create_cancel_path missing id" >&2
  echo "$(http_body_from_raw "$raw")" >&2
  exit 1
fi

raw="$(
  signed_payments_call \
    POST \
    "/requests/${request_cancel_id}/cancel?wallet_id=${wallet_a}" \
    "" \
    -H "Idempotency-Key: smk-request-cancel-final-$(openssl rand -hex 4)"
)"
assert_status "request_cancel" "$raw" "200"

raw="$(
  signed_payments_call \
    POST \
    "/favorites" \
    "{\"owner_wallet_id\":\"${wallet_a}\",\"favorite_wallet_id\":\"${wallet_b}\",\"alias\":\"smoke-favorite\"}" \
    -H "Idempotency-Key: ${ikey_favorite_create}"
)"
assert_status "favorite_create" "$raw" "200"
favorite_id="$(http_body_from_raw "$raw" | jq -r '.id // empty')"
if [[ -z "$favorite_id" ]]; then
  echo "smoke-payments-moneyflow: favorite_create missing id" >&2
  echo "$(http_body_from_raw "$raw")" >&2
  exit 1
fi

raw="$(signed_payments_call GET "/favorites?owner_wallet_id=${wallet_a}" "")"
assert_status "favorites_list" "$raw" "200"

raw="$(
  signed_payments_call \
    DELETE \
    "/favorites/${favorite_id}?owner_wallet_id=${wallet_a}" \
    "" \
    -H "Idempotency-Key: ${ikey_favorite_delete}"
)"
assert_status "favorite_delete" "$raw" "200"

raw="$(signed_payments_call GET "/wallets/${wallet_a}/snapshot?limit=20" "")"
assert_status "wallet_snapshot_a" "$raw" "200"
raw="$(signed_payments_call GET "/wallets/${wallet_b}/snapshot?limit=20" "")"
assert_status "wallet_snapshot_b" "$raw" "200"

transfer_endpoint="transfer:${wallet_a}:wallet:${wallet_b}"
raw="$(signed_payments_call GET "/idempotency/${ikey_transfer}?endpoint=${transfer_endpoint}" "")"
assert_status "idempotency_lookup_transfer" "$raw" "200"
if [[ "$(http_body_from_raw "$raw" | jq -r '.exists // false')" != "true" ]]; then
  echo "smoke-payments-moneyflow: idempotency transfer lookup did not return exists=true" >&2
  echo "$(http_body_from_raw "$raw")" >&2
  exit 1
fi

echo "smoke-payments-moneyflow: ok (wallet_a=${wallet_a} wallet_b=${wallet_b} topup=${topup_amount_cents} transfer=${transfer_amount_cents} request=${request_amount_cents})"
