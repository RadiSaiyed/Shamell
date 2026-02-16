#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/ops/dev-proxy/dashboard.conf.template"
TEMPLATE_TLS="${ROOT}/ops/dev-proxy/dashboard.tls.conf.template"
ENV_FILE="${DASHBOARD_PROXY_ENV_FILE:-${ROOT}/ops/pi/.env}"
NGINX_IMAGE="${DASHBOARD_PROXY_NGINX_IMAGE:-nginx:1.27-alpine@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10}"
NETWORK="${DASHBOARD_PROXY_DOCKER_NETWORK:-pi_default}"
CERT_DIR="${DASHBOARD_PROXY_CERT_DIR:-${ROOT}/ops/dev-proxy/certs}"

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

if [[ ! "${NGINX_IMAGE}" =~ @sha256:[a-f0-9]{64}$ ]]; then
  echo "DASHBOARD_PROXY_NGINX_IMAGE must be digest-pinned (expected ...@sha256:...)" >&2
  exit 1
fi

start_proxy() {
  local name="$1"
  local port="$2"
  local upstream_port="$3"
  local secret_key="$4"
  local caller_id="$5"
  local auth_roles="${6:-}"
  local role_auth_secret_key="${7:-}"

  local container=""
  if [[ "$name" == "bff" ]]; then
    container="${DASHBOARD_PROXY_CONTAINER_BFF:-shamell-dashboard-proxy}"
  else
    container="${DASHBOARD_PROXY_CONTAINER_PREFIX:-shamell-dashboard-proxy}-${name}"
  fi

  local internal_secret="${!secret_key:-}"
  if [[ -z "${internal_secret//[[:space:]]/}" ]]; then
    internal_secret="$(read_env_file "$secret_key" "$ENV_FILE")"
  fi
  if [[ -z "${internal_secret//[[:space:]]/}" ]]; then
    echo "Missing ${secret_key} (set env var or ${ENV_FILE}); refusing to start ${name} proxy." >&2
    exit 1
  fi

  local role_auth=""
  if [[ -n "${role_auth_secret_key//[[:space:]]/}" ]]; then
    role_auth="${!role_auth_secret_key:-}"
    if [[ -z "${role_auth//[[:space:]]/}" ]]; then
      role_auth="$(read_env_file "$role_auth_secret_key" "$ENV_FILE")"
    fi
  fi
  if [[ -n "${auth_roles//[[:space:]]/}" && -z "${role_auth_secret_key//[[:space:]]/}" ]]; then
    echo "Missing role-auth secret key mapping for ${name} while AUTH_ROLES is set." >&2
    exit 1
  fi
  if [[ -n "${auth_roles//[[:space:]]/}" && -z "${role_auth//[[:space:]]/}" ]]; then
    echo "Missing ${role_auth_secret_key} while AUTH_ROLES is set for ${name} proxy." >&2
    exit 1
  fi

  docker rm -f "${container}" >/dev/null 2>&1 || true

  docker run -d \
    --name "${container}" \
    --network "${NETWORK}" \
    -p "127.0.0.1:${port}:80" \
    -e INTERNAL_SECRET="${internal_secret}" \
    -e CALLER_ID="${caller_id}" \
    -e AUTH_ROLES="${auth_roles}" \
    -e ROLE_AUTH="${role_auth}" \
    -e UPSTREAM_HOSTPORT="${name}:${upstream_port}" \
    -e UPSTREAM_HOST_HEADER="127.0.0.1:${upstream_port}" \
    -v "${TEMPLATE}:/etc/nginx/templates/default.conf.template:ro" \
    "${NGINX_IMAGE}" >/dev/null

  local roles_note=""
  if [[ -n "${auth_roles//[[:space:]]/}" ]]; then
    roles_note=", roles=${auth_roles}"
  fi
  echo "  ${name}: http://127.0.0.1:${port} -> 127.0.0.1:${upstream_port} (${secret_key}, caller=${caller_id}${roles_note})"
}

start_proxy_tls() {
  local name="$1"
  local port="$2"
  local upstream_port="$3"
  local secret_key="$4"
  local caller_id="$5"
  local auth_roles="${6:-}"
  local role_auth_secret_key="${7:-}"

  if [[ ! -f "${TEMPLATE_TLS}" ]]; then
    echo "Missing TLS template: ${TEMPLATE_TLS}" >&2
    exit 1
  fi
  "${ROOT}/scripts/ensure_dev_proxy_cert.sh" >/dev/null

  local container="${DASHBOARD_PROXY_CONTAINER_BFF_TLS:-shamell-dashboard-proxy-bff-tls}"

  local internal_secret="${!secret_key:-}"
  if [[ -z "${internal_secret//[[:space:]]/}" ]]; then
    internal_secret="$(read_env_file "$secret_key" "$ENV_FILE")"
  fi
  if [[ -z "${internal_secret//[[:space:]]/}" ]]; then
    echo "Missing ${secret_key} (set env var or ${ENV_FILE}); refusing to start ${name} proxy." >&2
    exit 1
  fi

  local role_auth=""
  if [[ -n "${role_auth_secret_key//[[:space:]]/}" ]]; then
    role_auth="${!role_auth_secret_key:-}"
    if [[ -z "${role_auth//[[:space:]]/}" ]]; then
      role_auth="$(read_env_file "$role_auth_secret_key" "$ENV_FILE")"
    fi
  fi
  if [[ -n "${auth_roles//[[:space:]]/}" && -z "${role_auth_secret_key//[[:space:]]/}" ]]; then
    echo "Missing role-auth secret key mapping for ${name} while AUTH_ROLES is set." >&2
    exit 1
  fi
  if [[ -n "${auth_roles//[[:space:]]/}" && -z "${role_auth//[[:space:]]/}" ]]; then
    echo "Missing ${role_auth_secret_key} while AUTH_ROLES is set for ${name} proxy." >&2
    exit 1
  fi

  docker rm -f "${container}" >/dev/null 2>&1 || true

  docker run -d \
    --name "${container}" \
    --network "${NETWORK}" \
    -p "127.0.0.1:${port}:443" \
    -e INTERNAL_SECRET="${internal_secret}" \
    -e CALLER_ID="${caller_id}" \
    -e AUTH_ROLES="${auth_roles}" \
    -e ROLE_AUTH="${role_auth}" \
    -e UPSTREAM_HOSTPORT="${name}:${upstream_port}" \
    -e UPSTREAM_HOST_HEADER="127.0.0.1:${upstream_port}" \
    -v "${TEMPLATE_TLS}:/etc/nginx/templates/default.conf.template:ro" \
    -v "${CERT_DIR}:/etc/nginx/certs:ro" \
    "${NGINX_IMAGE}" >/dev/null

  local roles_note=""
  if [[ -n "${auth_roles//[[:space:]]/}" ]]; then
    roles_note=", roles=${auth_roles}"
  fi
  echo "  ${name} (tls): https://127.0.0.1:${port} -> 127.0.0.1:${upstream_port} (${secret_key}, caller=${caller_id}${roles_note})"
}

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Missing template: ${TEMPLATE}" >&2
  exit 1
fi

echo "Starting Shamell dashboard dev proxies (127.0.0.1 only):"

# BFF expects edge-injected internal auth.
start_proxy "bff" "${DASHBOARD_PROXY_PORT_BFF:-8090}" 8080 "INTERNAL_API_SECRET" "${DASHBOARD_PROXY_CALLER_BFF:-edge}" "${DASHBOARD_PROXY_AUTH_ROLES_BFF:-}" "BFF_ROLE_HEADER_SECRET"

# Browser sessions require TLS to accept Secure cookies.
if truthy "${DASHBOARD_PROXY_BFF_TLS:-true}"; then
  start_proxy_tls "bff" "${DASHBOARD_PROXY_PORT_BFF_TLS:-8443}" 8080 "INTERNAL_API_SECRET" "${DASHBOARD_PROXY_CALLER_BFF:-edge}" "${DASHBOARD_PROXY_AUTH_ROLES_BFF:-}" "BFF_ROLE_HEADER_SECRET"
fi

# Internal services expect the BFF as caller.
start_proxy "chat" "${DASHBOARD_PROXY_PORT_CHAT:-8091}" 8081 "CHAT_INTERNAL_SECRET" "${DASHBOARD_PROXY_CALLER_CHAT:-bff}"
start_proxy "payments" "${DASHBOARD_PROXY_PORT_PAYMENTS:-8092}" 8082 "PAYMENTS_INTERNAL_SECRET" "${DASHBOARD_PROXY_CALLER_PAYMENTS:-bff}"
start_proxy "bus" "${DASHBOARD_PROXY_PORT_BUS:-8093}" 8083 "BUS_INTERNAL_SECRET" "${DASHBOARD_PROXY_CALLER_BUS:-bff}"

echo
echo "Tip: open /health on each to verify."
echo "  http:  http://127.0.0.1:${DASHBOARD_PROXY_PORT_BFF:-8090}/health"
echo "  https: https://127.0.0.1:${DASHBOARD_PROXY_PORT_BFF_TLS:-8443}/health (self-signed, browser warning expected)"
