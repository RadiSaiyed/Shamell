#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${APP_DIR}/scripts/lib_internal_identity.sh"

ENV_FILE="${ENV_FILE:-${APP_DIR}/ops/pi/.env}"
BASE_URL="${ACCESS_ASSIGNMENT_ADMIN_BASE_URL:-}"
SERVICE_ID="${ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID:-control-automation}"
SIGNING_SEED_B64="${ACCESS_ASSIGNMENT_ADMIN_SIGNING_SEED_B64:-}"
AUDIENCE="${ACCESS_ASSIGNMENT_ADMIN_AUDIENCE:-bff}"
DRY_RUN=0
COMPACT=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/access_assignment_admin.sh keygen [--service-id <id>] [--audience <aud>]
  scripts/access_assignment_admin.sh list --account-id <id>|--phone <phone> [filters...]
  scripts/access_assignment_admin.sh add --role-id <role_id> (--account-id <id>|--phone <phone>) [scope...]
  scripts/access_assignment_admin.sh remove --role-id <role_id> (--account-id <id>|--phone <phone>) [scope...]

Common options:
  --env-file <path>     env file to read defaults from (default: ops/pi/.env)
  --base-url <url>      BFF base URL (default: ACCESS_ASSIGNMENT_ADMIN_BASE_URL or derived from BFF_PUBLISH_ADDR/BFF_PUBLISH_PORT)
  --service-id <id>     internal caller id used for signing (default: control-automation)
  --seed-b64 <seed>     Ed25519 seed base64 for signing
  --audience <aud>      internal identity audience (default: bff)
  --dry-run             print request instead of sending it
  --compact             print compact JSON instead of pretty output

List filters:
  --account-id <id>
  --phone <phone>
  --role-id <role_id>
  --operator-id <id>
  --official-account-id <id>
  --limit <n>
  --before-created-at <iso>
  --before-id <id>

Add/remove scope:
  --account-id <id>
  --phone <phone>
  --role-id <role_id>
  --platform
  --operator-id <id>
  --official-account-id <id>

Examples:
  scripts/access_assignment_admin.sh keygen --service-id control-automation
  scripts/access_assignment_admin.sh list --phone +963944444444
  scripts/access_assignment_admin.sh add --phone +963944444444 --role-id platform.admin --platform
  scripts/access_assignment_admin.sh remove --phone +963944444444 --role-id official.account_owner --official-account-id shamell_pay
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

read_env_file_var() {
  local key="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    return 0
  fi
  local line
  line="$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE" | tail -n1 || true)"
  line="${line#*=}"
  line="${line%\"}"
  line="${line#\"}"
  printf "%s" "$line"
}

trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "$value"
}

b64_file() {
  local file="$1"
  if base64 --help 2>/dev/null | grep -q -- '-w'; then
    base64 -w0 "$file"
  else
    base64 <"$file" | tr -d '\n'
  fi
}

b64_stdin() {
  if base64 --help 2>/dev/null | grep -q -- '-w'; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

generate_internal_identity_pair() {
  local key_file text priv_hex pub_hex priv_b64 pub_b64
  key_file="$(mktemp)"
  openssl genpkey -algorithm ED25519 -out "$key_file" >/dev/null 2>&1
  text="$(openssl pkey -in "$key_file" -text -noout)"
  rm -f "$key_file"
  priv_hex="$(
    printf '%s\n' "$text" |
      awk '
        /^priv:$/ {capture=1; next}
        /^pub:$/ {capture=0}
        capture {print}
      ' |
      tr -d '[:space:]:'
  )"
  pub_hex="$(
    printf '%s\n' "$text" |
      awk '/^pub:$/ {capture=1; next} capture {print}' |
      tr -d '[:space:]:'
  )"
  priv_b64="$(printf '%s' "$priv_hex" | xxd -r -p | b64_stdin)"
  pub_b64="$(printf '%s' "$pub_hex" | xxd -r -p | b64_stdin)"
  printf '%s %s\n' "$priv_b64" "$pub_b64"
}

derive_base_url() {
  local base="$BASE_URL"
  if [[ -z "$base" ]]; then
    base="$(read_env_file_var ACCESS_ASSIGNMENT_ADMIN_BASE_URL)"
  fi
  if [[ -z "$base" ]]; then
    local publish_addr publish_port
    publish_addr="$(read_env_file_var BFF_PUBLISH_ADDR)"
    publish_port="$(read_env_file_var BFF_PUBLISH_PORT)"
    publish_addr="${publish_addr:-127.0.0.1}"
    publish_port="${publish_port:-8080}"
    if [[ "$publish_addr" == "0.0.0.0" ]]; then
      publish_addr="127.0.0.1"
    fi
    base="http://${publish_addr}:${publish_port}"
  fi
  printf '%s' "${base%/}"
}

url_encode() {
  python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

pretty_print_json() {
  local payload="$1"
  if [[ "$COMPACT" == "1" ]]; then
    printf '%s\n' "$payload"
    return 0
  fi
  if have_cmd jq; then
    printf '%s\n' "$payload" | jq .
    return 0
  fi
  python3 -m json.tool <<<"$payload"
}

build_query_url() {
  local base_url="$1"
  shift
  local pairs=("$@")
  local url="${base_url}/internal/admin/access/assignments"
  local first=1
  local pair key value
  for pair in "${pairs[@]}"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    [[ -z "$key" ]] && continue
    if [[ "$first" == "1" ]]; then
      url="${url}?"
      first=0
    else
      url="${url}&"
    fi
    url="${url}$(url_encode "$key")=$(url_encode "$value")"
  done
  printf '%s' "$url"
}

build_mutation_payload() {
  local account_id="$1"
  local phone="$2"
  local role_id="$3"
  local platform="$4"
  local operator_id="$5"
  local official_account_id="$6"
  python3 - "$account_id" "$phone" "$role_id" "$platform" "$operator_id" "$official_account_id" <<'PY'
import json
import sys

account_id, phone, role_id, platform, operator_id, official_account_id = sys.argv[1:]
body = {"role_id": role_id}
if account_id:
    body["account_id"] = account_id
if phone:
    body["phone"] = phone
scope = {}
if platform == "1":
    scope["platform"] = True
if operator_id:
    scope["operator_id"] = operator_id
if official_account_id:
    scope["official_account_id"] = official_account_id
if scope:
    body["scope"] = scope
print(json.dumps(body, separators=(",", ":")))
PY
}

send_signed_request() {
  local method="$1"
  local url="$2"
  local payload="${3:-}"
  local body_file response_file
  body_file="$(mktemp)"
  response_file="$(mktemp)"
  trap 'rm -f "$body_file" "$response_file"' RETURN
  printf '%s' "$payload" >"$body_file"

  if [[ -z "$SIGNING_SEED_B64" ]]; then
    SIGNING_SEED_B64="$(read_env_file_var ACCESS_ASSIGNMENT_ADMIN_SIGNING_SEED_B64)"
  fi
  if [[ -z "$SIGNING_SEED_B64" ]]; then
    echo "ACCESS_ASSIGNMENT_ADMIN_SIGNING_SEED_B64 is required (env var or ${ENV_FILE})." >&2
    exit 1
  fi
  if [[ -z "$SERVICE_ID" ]]; then
    SERVICE_ID="$(read_env_file_var ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID)"
  fi
  SERVICE_ID="$(internal_identity_normalize_service_id "${SERVICE_ID:-control-automation}")"
  if [[ -z "$AUDIENCE" ]]; then
    AUDIENCE="$(read_env_file_var ACCESS_ASSIGNMENT_ADMIN_AUDIENCE)"
  fi
  AUDIENCE="$(internal_identity_normalize_audience "${AUDIENCE:-bff}")"

  local -a curl_args
  curl_args=(-sS -X "$method" -H "Content-Type: application/json")
  while IFS= read -r header; do
    curl_args+=(-H "$header")
  done < <(
    internal_identity_build_curl_headers \
      "$SIGNING_SEED_B64" \
      "$SERVICE_ID" \
      "$AUDIENCE" \
      "$method" \
      "$url" \
      "$body_file"
  )
  if [[ "$method" != "GET" ]]; then
    curl_args+=(--data-binary "@${body_file}")
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "Dry run:"
    echo "  method: ${method}"
    echo "  url: ${url}"
    echo "  service_id: ${SERVICE_ID}"
    echo "  audience: ${AUDIENCE}"
    if [[ -n "$payload" ]]; then
      echo "  payload:"
      pretty_print_json "$payload"
    fi
    return 0
  fi

  local status
  status="$(curl "${curl_args[@]}" -o "$response_file" -w '%{http_code}' "$url")"
  local response
  response="$(cat "$response_file")"
  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    echo "Request failed: HTTP ${status}" >&2
    if [[ -n "$response" ]]; then
      pretty_print_json "$response" >&2 || printf '%s\n' "$response" >&2
    fi
    exit 1
  fi
  if [[ -n "$response" ]]; then
    pretty_print_json "$response"
  fi
}

COMMAND="${1:-}"
if [[ -z "$COMMAND" ]]; then
  usage
  exit 1
fi
shift || true

ACCOUNT_ID=""
PHONE=""
ROLE_ID=""
OPERATOR_ID=""
OFFICIAL_ACCOUNT_ID=""
PLATFORM_SCOPE=0
LIMIT=""
BEFORE_CREATED_AT=""
BEFORE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    --service-id)
      SERVICE_ID="$2"
      shift 2
      ;;
    --seed-b64)
      SIGNING_SEED_B64="$2"
      shift 2
      ;;
    --audience)
      AUDIENCE="$2"
      shift 2
      ;;
    --account-id)
      ACCOUNT_ID="$2"
      shift 2
      ;;
    --phone)
      PHONE="$2"
      shift 2
      ;;
    --role-id)
      ROLE_ID="$2"
      shift 2
      ;;
    --operator-id)
      OPERATOR_ID="$2"
      shift 2
      ;;
    --official-account-id)
      OFFICIAL_ACCOUNT_ID="$2"
      shift 2
      ;;
    --platform)
      PLATFORM_SCOPE=1
      shift
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --before-created-at)
      BEFORE_CREATED_AT="$2"
      shift 2
      ;;
    --before-id)
      BEFORE_ID="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --compact)
      COMPACT=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd curl
require_cmd python3
require_cmd openssl
require_cmd xxd

BASE_URL="$(derive_base_url)"

case "$COMMAND" in
  keygen)
    read -r seed_b64 pub_b64 < <(generate_internal_identity_pair)
    SERVICE_ID="$(internal_identity_normalize_service_id "${SERVICE_ID:-control-automation}")"
    AUDIENCE="$(internal_identity_normalize_audience "${AUDIENCE:-bff}")"
    cat <<EOF
ACCESS_ASSIGNMENT_ADMIN_SERVICE_ID=${SERVICE_ID}
ACCESS_ASSIGNMENT_ADMIN_SIGNING_SEED_B64=${seed_b64}
ACCESS_ASSIGNMENT_ADMIN_AUDIENCE=${AUDIENCE}
BFF_ACCESS_ASSIGNMENT_ALLOWED_CALLERS=${SERVICE_ID}
BFF_ACCESS_ASSIGNMENT_INTERNAL_IDENTITY_PUBLIC_KEYS=${SERVICE_ID}=${pub_b64}
EOF
    ;;
  list)
    if [[ -z "$(trim "$ACCOUNT_ID")" && -z "$(trim "$PHONE")" ]]; then
      echo "list requires --account-id or --phone" >&2
      exit 1
    fi
    declare -a query=()
    [[ -n "$(trim "$ACCOUNT_ID")" ]] && query+=("account_id=${ACCOUNT_ID}")
    [[ -n "$(trim "$PHONE")" ]] && query+=("phone=${PHONE}")
    [[ -n "$(trim "$ROLE_ID")" ]] && query+=("role_id=${ROLE_ID}")
    [[ -n "$(trim "$OPERATOR_ID")" ]] && query+=("operator_id=${OPERATOR_ID}")
    [[ -n "$(trim "$OFFICIAL_ACCOUNT_ID")" ]] && query+=("official_account_id=${OFFICIAL_ACCOUNT_ID}")
    [[ -n "$(trim "$LIMIT")" ]] && query+=("limit=${LIMIT}")
    [[ -n "$(trim "$BEFORE_CREATED_AT")" ]] && query+=("before_created_at=${BEFORE_CREATED_AT}")
    [[ -n "$(trim "$BEFORE_ID")" ]] && query+=("before_id=${BEFORE_ID}")
    send_signed_request "GET" "$(build_query_url "$BASE_URL" "${query[@]}")" ""
    ;;
  add|remove)
    if [[ -z "$(trim "$ROLE_ID")" ]]; then
      echo "${COMMAND} requires --role-id" >&2
      exit 1
    fi
    if [[ -z "$(trim "$ACCOUNT_ID")" && -z "$(trim "$PHONE")" ]]; then
      echo "${COMMAND} requires --account-id or --phone" >&2
      exit 1
    fi
    payload="$(build_mutation_payload "$ACCOUNT_ID" "$PHONE" "$ROLE_ID" "$PLATFORM_SCOPE" "$OPERATOR_ID" "$OFFICIAL_ACCOUNT_ID")"
    if [[ "$COMMAND" == "add" ]]; then
      send_signed_request "POST" "${BASE_URL}/internal/admin/access/assignments" "$payload"
    else
      send_signed_request "DELETE" "${BASE_URL}/internal/admin/access/assignments" "$payload"
    fi
    ;;
  *)
    echo "Unknown command: ${COMMAND}" >&2
    usage >&2
    exit 1
    ;;
esac
