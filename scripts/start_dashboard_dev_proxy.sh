#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/ops/dev-proxy/dashboard.conf.template"
TEMPLATE_TLS="${ROOT}/ops/dev-proxy/dashboard.tls.conf.template"
PORT="${DASHBOARD_PROXY_PORT:-8090}"
CONTAINER="${DASHBOARD_PROXY_CONTAINER:-shamell-dashboard-proxy}"
CALLER_ID="${DASHBOARD_PROXY_CALLER_ID:-edge}"
ENV_FILE="${DASHBOARD_PROXY_ENV_FILE:-${ROOT}/ops/pi/.env}"
UPSTREAM_HOSTPORT="${DASHBOARD_PROXY_UPSTREAM_HOSTPORT:-host.docker.internal:8080}"
UPSTREAM_HOST_HEADER="${DASHBOARD_PROXY_UPSTREAM_HOST_HEADER:-127.0.0.1:8080}"
CERT_DIR="${DASHBOARD_PROXY_CERT_DIR:-${ROOT}/ops/dev-proxy/certs}"
NGINX_IMAGE="${DASHBOARD_PROXY_NGINX_IMAGE:-nginx:1.27-alpine@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10}"
ROLE_AUTH_KEY="${DASHBOARD_PROXY_ROLE_AUTH_ENV_KEY:-BFF_ROLE_HEADER_SECRET}"
ALLOW_UNTRUSTED_CLIENT_IP="${DASHBOARD_PROXY_ALLOW_UNTRUSTED_CLIENT_IP:-}"

truthy() {
  local v="${1:-}"
  v="$(echo "${v}" | tr '[:upper:]' '[:lower:]' | xargs)"
  [[ -n "$v" && ! "$v" =~ ^(0|false|no|off)$ ]]
}

read_env_file() {
  local key="$1"
  local file="$2"
  if [[ -z "$file" || ! -f "$file" ]]; then
    return 0
  fi
  local line
  line="$(grep -E "^[[:space:]]*${key}=" "$file" | tail -n1 || true)"
  line="${line#*=}"
  line="${line%\"}"
  line="${line#\"}"
  printf "%s" "$line"
}

normalize_csv() {
  local raw="$1"
  raw="${raw//$'\n'/,}"
  raw="${raw//;/,}"
  printf '%s' "$raw"
}

trusted_proxy_cidrs_are_loopback_only() {
  local raw="$1"
  local normalized token seen_nonempty=0
  normalized="$(normalize_csv "$raw")"
  IFS=',' read -r -a cidrs <<<"$normalized"
  for token in "${cidrs[@]}"; do
    token="$(printf '%s' "$token" | xargs)"
    [[ -n "$token" ]] || continue
    seen_nonempty=1
    case "$token" in
      127.0.0.1/32|::1/128|127.0.0.0/8)
        ;;
      *)
        return 1
        ;;
    esac
  done
  (( seen_nonempty == 0 )) && return 0
  return 0
}

enforce_trusted_proxy_config_for_dashboard_proxy() {
  local trusted_proxy_cidrs="$1"
  if truthy "$ALLOW_UNTRUSTED_CLIENT_IP"; then
    return 0
  fi
  if trusted_proxy_cidrs_are_loopback_only "$trusted_proxy_cidrs"; then
    echo "BFF_TRUSTED_PROXY_CIDRS is loopback-only for dashboard proxy startup." >&2
    echo "This proxy runs in Docker, so the BFF sees a non-loopback immediate peer and will ignore X-Forwarded-For from this proxy." >&2
    echo "Add the Docker bridge/gateway CIDR used by the dashboard proxy hop to BFF_TRUSTED_PROXY_CIDRS, or set DASHBOARD_PROXY_ALLOW_UNTRUSTED_CLIENT_IP=1 to continue without trusted client-IP simulation." >&2
    exit 1
  fi
}

INTERNAL_SECRET="${INTERNAL_API_SECRET:-}"
if [[ -z "${INTERNAL_SECRET//[[:space:]]/}" ]]; then
  INTERNAL_SECRET="$(read_env_file INTERNAL_API_SECRET "$ENV_FILE")"
fi
if [[ -z "${INTERNAL_SECRET//[[:space:]]/}" ]]; then
  echo "INTERNAL_API_SECRET is required (set env var or ${ENV_FILE})." >&2
  exit 1
fi

TRUSTED_PROXY_CIDRS="${BFF_TRUSTED_PROXY_CIDRS:-}"
if [[ -z "${TRUSTED_PROXY_CIDRS//[[:space:]]/}" ]]; then
  TRUSTED_PROXY_CIDRS="$(read_env_file BFF_TRUSTED_PROXY_CIDRS "$ENV_FILE")"
fi
enforce_trusted_proxy_config_for_dashboard_proxy "$TRUSTED_PROXY_CIDRS"

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Missing template: ${TEMPLATE}" >&2
  exit 1
fi

if [[ ! "${NGINX_IMAGE}" =~ @sha256:[a-f0-9]{64}$ ]]; then
  echo "DASHBOARD_PROXY_NGINX_IMAGE must be digest-pinned (expected ...@sha256:...)" >&2
  exit 1
fi

AUTH_ROLES="${DASHBOARD_PROXY_AUTH_ROLES:-}"
ROLE_AUTH="${DASHBOARD_PROXY_ROLE_AUTH:-}"
if [[ -z "${ROLE_AUTH//[[:space:]]/}" ]]; then
  ROLE_AUTH="$(read_env_file "${ROLE_AUTH_KEY}" "$ENV_FILE")"
fi
if [[ -n "${AUTH_ROLES//[[:space:]]/}" && -z "${ROLE_AUTH//[[:space:]]/}" ]]; then
  echo "Missing role-auth secret (${ROLE_AUTH_KEY}) while DASHBOARD_PROXY_AUTH_ROLES is set." >&2
  exit 1
fi

docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true

PORT_MAP="127.0.0.1:${PORT}:80"
TEMPLATE_USE="${TEMPLATE}"
EXTRA_MOUNTS=()
if truthy "${DASHBOARD_PROXY_TLS:-false}"; then
  if [[ ! -f "${TEMPLATE_TLS}" ]]; then
    echo "Missing TLS template: ${TEMPLATE_TLS}" >&2
    exit 1
  fi
  "${ROOT}/scripts/ensure_dev_proxy_cert.sh" >/dev/null
  PORT_MAP="127.0.0.1:${PORT}:443"
  TEMPLATE_USE="${TEMPLATE_TLS}"
  EXTRA_MOUNTS=(-v "${CERT_DIR}:/etc/nginx/certs:ro")
fi

docker run -d \
  --name "${CONTAINER}" \
  -p "${PORT_MAP}" \
  -e INTERNAL_SECRET="${INTERNAL_SECRET}" \
  -e CALLER_ID="${CALLER_ID}" \
  -e AUTH_ROLES="${AUTH_ROLES}" \
  -e ROLE_AUTH="${ROLE_AUTH}" \
  -e UPSTREAM_HOSTPORT="${UPSTREAM_HOSTPORT}" \
  -e UPSTREAM_HOST_HEADER="${UPSTREAM_HOST_HEADER}" \
  -v "${TEMPLATE_USE}:/etc/nginx/templates/default.conf.template:ro" \
  "${EXTRA_MOUNTS[@]}" \
  "${NGINX_IMAGE}" >/dev/null

echo "Dashboard dev proxy is up:"
if truthy "${DASHBOARD_PROXY_TLS:-false}"; then
  echo "  URL: https://127.0.0.1:${PORT} (self-signed)"
else
  echo "  URL: http://127.0.0.1:${PORT}"
fi
echo "  Container: ${CONTAINER}"
echo "  Caller ID header: ${CALLER_ID}"
echo "  Upstream: ${UPSTREAM_HOSTPORT}"
echo "  BFF_TRUSTED_PROXY_CIDRS: ${TRUSTED_PROXY_CIDRS}"
