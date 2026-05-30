#!/usr/bin/env bash
set -euo pipefail

HOST_ALIAS="${1:-shamell}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITES_DIR="${REPO_ROOT}/ops/hetzner/nginx/sites-available"
SNIPPETS_DIR="${REPO_ROOT}/ops/hetzner/nginx/snippets"
CONF_DIR="${REPO_ROOT}/ops/hetzner/nginx/conf.d"
DOCS_ALLOWLIST_IPS="${DOCS_ALLOWLIST_IPS:-}"
NGINX_SYNC_ENV_FILE="${NGINX_SYNC_ENV_FILE:-${REPO_ROOT}/ops/pi/.env}"
NGINX_INTERNAL_API_SECRET="${NGINX_INTERNAL_API_SECRET:-}"
tmp_local_docs_allowlist=""
tmp_local_internal_auth=""

cleanup() {
  if [[ -n "$tmp_local_docs_allowlist" ]] && [[ -f "$tmp_local_docs_allowlist" ]]; then
    rm -f "$tmp_local_docs_allowlist"
  fi
  if [[ -n "$tmp_local_internal_auth" ]] && [[ -f "$tmp_local_internal_auth" ]]; then
    rm -f "$tmp_local_internal_auth"
  fi
}

trap cleanup EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd ssh
require_cmd scp

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

build_docs_allowlist_snippet() {
  local path="$1"
  local raw="$2"
  local token=""
  local normalized=""

  cat >"$path" <<'EOF'
# Managed by scripts/sync_hetzner_nginx.sh
# Host-local allowlist for `/docs` and `/openapi.json`.
allow 127.0.0.1;
allow ::1;
EOF

  normalized="${raw//$'\n'/ }"
  normalized="${normalized//,/ }"
  normalized="${normalized//;/ }"

  for token in $normalized; do
    token="${token//[[:space:]]/}"
    if [[ -z "$token" ]]; then
      continue
    fi
    if [[ "$token" == "127.0.0.1" ]] || [[ "$token" == "::1" ]]; then
      continue
    fi
    if [[ ! "$token" =~ ^[0-9A-Fa-f:.\/]+$ ]]; then
      echo "Invalid DOCS_ALLOWLIST_IPS entry: $token" >&2
      exit 1
    fi
    printf 'allow %s;\n' "$token" >>"$path"
  done
}

escape_nginx_value() {
  # Escape for use inside a double-quoted nginx directive value.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//\$/\\\$}"
  printf "%s" "$s"
}

build_internal_auth_snippet() {
  local path="$1"
  local secret="$2"
  local escaped
  escaped="$(escape_nginx_value "$secret")"
  cat >"$path" <<EOF
# Managed by scripts/sync_hetzner_nginx.sh (DO NOT COMMIT REAL SECRETS)
proxy_set_header X-Internal-Secret "${escaped}";
EOF
}

if [[ ! -d "$SITES_DIR" ]]; then
  echo "Missing source dir: $SITES_DIR" >&2
  exit 1
fi

internal_secret="${NGINX_INTERNAL_API_SECRET:-${INTERNAL_API_SECRET:-}}"
if [[ -z "${internal_secret//[[:space:]]/}" ]] && [[ -f "$NGINX_SYNC_ENV_FILE" ]]; then
  internal_secret="$(read_env_file INTERNAL_API_SECRET "$NGINX_SYNC_ENV_FILE")"
fi

if [[ -n "${internal_secret//[[:space:]]/}" ]] && [[ "$internal_secret" != change-me* ]]; then
  tmp_local_internal_auth="$(mktemp "${TMPDIR:-/tmp}/shamell-internal-auth.XXXXXX")"
  build_internal_auth_snippet "$tmp_local_internal_auth" "$internal_secret"
  echo "Rendering internal-auth snippet (X-Internal-Secret) from local env."
else
  echo "WARNING: INTERNAL_API_SECRET not provided; will not overwrite host-local internal-auth snippet."
  echo "         Set NGINX_INTERNAL_API_SECRET or INTERNAL_API_SECRET, or provide NGINX_SYNC_ENV_FILE with INTERNAL_API_SECRET."
fi

if [[ -n "${DOCS_ALLOWLIST_IPS//[[:space:],;]/}" ]]; then
  tmp_local_docs_allowlist="$(mktemp "${TMPDIR:-/tmp}/shamell-docs-allowlist.XXXXXX")"
  build_docs_allowlist_snippet "$tmp_local_docs_allowlist" "$DOCS_ALLOWLIST_IPS"
  echo "Using DOCS_ALLOWLIST_IPS to render docs allowlist snippet."
fi

tmp_remote="/tmp/shamell-nginx-sync-$$"

echo "Copying Nginx configs to ${HOST_ALIAS}:${tmp_remote}"
ssh "$HOST_ALIAS" "mkdir -p '$tmp_remote'"
scp "$SITES_DIR"/* "${HOST_ALIAS}:${tmp_remote}/"

if [[ -d "$SNIPPETS_DIR" ]]; then
  echo "Copying Nginx snippets to ${HOST_ALIAS}:${tmp_remote}/snippets"
  ssh "$HOST_ALIAS" "mkdir -p '$tmp_remote/snippets'"
  scp "$SNIPPETS_DIR"/* "${HOST_ALIAS}:${tmp_remote}/snippets/"
  if [[ -n "$tmp_local_docs_allowlist" ]]; then
    scp "$tmp_local_docs_allowlist" "${HOST_ALIAS}:${tmp_remote}/snippets/shamell_docs_allowlist.local.conf"
  fi
  if [[ -n "$tmp_local_internal_auth" ]]; then
    scp "$tmp_local_internal_auth" "${HOST_ALIAS}:${tmp_remote}/snippets/shamell_bff_internal_auth.local.conf"
  fi
fi

if [[ -d "$CONF_DIR" ]]; then
  echo "Copying Nginx conf.d to ${HOST_ALIAS}:${tmp_remote}/conf.d"
  ssh "$HOST_ALIAS" "mkdir -p '$tmp_remote/conf.d'"
  scp "$CONF_DIR"/* "${HOST_ALIAS}:${tmp_remote}/conf.d/"
fi

echo "Installing configs on ${HOST_ALIAS}"
ssh -tt "$HOST_ALIAS" "
  set -euo pipefail
  sudo install -d -m 0755 /etc/nginx/snippets
  sudo install -d -m 0755 /etc/nginx/conf.d

  if [[ -f '$tmp_remote/conf.d/shamell_log_formats.conf' ]]; then
    sudo install -m 0644 '$tmp_remote/conf.d/shamell_log_formats.conf' /etc/nginx/conf.d/shamell_log_formats.conf
  fi

  if [[ -f '$tmp_remote/snippets/shamell_cloudflare_realip.conf' ]]; then
    sudo install -m 0644 '$tmp_remote/snippets/shamell_cloudflare_realip.conf' /etc/nginx/snippets/shamell_cloudflare_realip.conf
  fi
  if [[ -f '$tmp_remote/snippets/shamell_bff_edge_hardening.conf' ]]; then
    sudo install -m 0644 '$tmp_remote/snippets/shamell_bff_edge_hardening.conf' /etc/nginx/snippets/shamell_bff_edge_hardening.conf
  fi
  if [[ -f '$tmp_remote/snippets/shamell_bff_internal_auth.local.conf' ]]; then
    sudo install -m 0600 '$tmp_remote/snippets/shamell_bff_internal_auth.local.conf' /etc/nginx/snippets/shamell_bff_internal_auth.local.conf
  fi
  if [[ ! -f /etc/nginx/snippets/shamell_bff_internal_auth.local.conf ]]; then
    echo 'ERROR: missing /etc/nginx/snippets/shamell_bff_internal_auth.local.conf' >&2
    echo '       Provide INTERNAL_API_SECRET to scripts/sync_hetzner_nginx.sh (or set it in NGINX_SYNC_ENV_FILE), or create the snippet manually.' >&2
    exit 1
  fi
  if ! sudo grep -qE 'proxy_set_header[[:space:]]+X-Internal-Secret[[:space:]]+\".+\";' /etc/nginx/snippets/shamell_bff_internal_auth.local.conf; then
    echo 'ERROR: /etc/nginx/snippets/shamell_bff_internal_auth.local.conf does not inject X-Internal-Secret.' >&2
    echo '       Edit the snippet or re-run scripts/sync_hetzner_nginx.sh with INTERNAL_API_SECRET.' >&2
    exit 1
  fi
  if [[ ! -f /etc/nginx/snippets/shamell_bff_role_attestation.local.conf ]] && [[ -f '$tmp_remote/snippets/shamell_bff_role_attestation.local.conf.example' ]]; then
    sudo install -m 0600 '$tmp_remote/snippets/shamell_bff_role_attestation.local.conf.example' /etc/nginx/snippets/shamell_bff_role_attestation.local.conf
  fi
  if [[ -f '$tmp_remote/snippets/shamell_docs_allowlist.local.conf' ]]; then
    sudo install -m 0644 '$tmp_remote/snippets/shamell_docs_allowlist.local.conf' /etc/nginx/snippets/shamell_docs_allowlist.local.conf
  elif [[ ! -f /etc/nginx/snippets/shamell_docs_allowlist.local.conf ]] && [[ -f '$tmp_remote/snippets/shamell_docs_allowlist.local.conf.example' ]]; then
    sudo install -m 0644 '$tmp_remote/snippets/shamell_docs_allowlist.local.conf.example' /etc/nginx/snippets/shamell_docs_allowlist.local.conf
  fi

  sudo install -m 0644 '$tmp_remote/api.shamell.online' /etc/nginx/sites-available/api.shamell.online
  if [[ -f '$tmp_remote/staging-api.shamell.online' ]]; then
    sudo install -m 0644 '$tmp_remote/staging-api.shamell.online' /etc/nginx/sites-available/staging-api.shamell.online
  fi
  if [[ -f '$tmp_remote/livekit.shamell.online' ]]; then
    sudo install -m 0644 '$tmp_remote/livekit.shamell.online' /etc/nginx/sites-available/livekit.shamell.online
  fi
  sudo install -m 0644 '$tmp_remote/media.shamell.online' /etc/nginx/sites-available/media.shamell.online
  sudo install -m 0644 '$tmp_remote/online.shamell.online' /etc/nginx/sites-available/online.shamell.online
  sudo install -m 0644 '$tmp_remote/shamell.online' /etc/nginx/sites-available/shamell.online

  sudo ln -sfn /etc/nginx/sites-available/api.shamell.online /etc/nginx/sites-enabled/api.shamell.online
  if [[ -f /etc/nginx/sites-available/staging-api.shamell.online ]]; then
    sudo ln -sfn /etc/nginx/sites-available/staging-api.shamell.online /etc/nginx/sites-enabled/staging-api.shamell.online
  fi
  if [[ -f /etc/nginx/sites-available/livekit.shamell.online ]]; then
    if [[ -f /etc/letsencrypt/live/livekit.shamell.online/fullchain.pem ]] && [[ -f /etc/letsencrypt/live/livekit.shamell.online/privkey.pem ]]; then
      sudo ln -sfn /etc/nginx/sites-available/livekit.shamell.online /etc/nginx/sites-enabled/livekit.shamell.online
    else
      sudo rm -f /etc/nginx/sites-enabled/livekit.shamell.online
    fi
  fi
  sudo ln -sfn /etc/nginx/sites-available/media.shamell.online /etc/nginx/sites-enabled/media.shamell.online
  sudo ln -sfn /etc/nginx/sites-available/online.shamell.online /etc/nginx/sites-enabled/online.shamell.online
  sudo ln -sfn /etc/nginx/sites-available/shamell.online /etc/nginx/sites-enabled/shamell.online

  sudo nginx -t
  sudo systemctl reload nginx
  rm -rf '$tmp_remote'
"

echo "Verifying local host route on ${HOST_ALIAS}"
ssh "$HOST_ALIAS" "curl -skfsS -H 'Host: api.shamell.online' https://127.0.0.1/health"
ssh "$HOST_ALIAS" "curl -skfsS -H 'Host: api.shamell.online' https://127.0.0.1/bus/health"

echo "Nginx sync complete."
