#!/usr/bin/env bash
set -euo pipefail

HOST_ALIAS="${1:-shamell}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${REPO_ROOT}/ops/hetzner/nginx/sites-available"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd ssh
require_cmd scp

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Missing source dir: $SRC_DIR" >&2
  exit 1
fi

tmp_remote="/tmp/shamell-nginx-sync-$$"

echo "Copying Nginx configs to ${HOST_ALIAS}:${tmp_remote}"
ssh "$HOST_ALIAS" "mkdir -p '$tmp_remote'"
scp "$SRC_DIR"/* "${HOST_ALIAS}:${tmp_remote}/"

echo "Installing configs on ${HOST_ALIAS}"
ssh -tt "$HOST_ALIAS" "
  set -euo pipefail
  sudo install -m 0644 '$tmp_remote/api.shamell.online' /etc/nginx/sites-available/api.shamell.online
  sudo install -m 0644 '$tmp_remote/media.shamell.online' /etc/nginx/sites-available/media.shamell.online
  sudo install -m 0644 '$tmp_remote/online.shamell.online' /etc/nginx/sites-available/online.shamell.online
  sudo install -m 0644 '$tmp_remote/shamell.online' /etc/nginx/sites-available/shamell.online

  sudo ln -sfn /etc/nginx/sites-available/api.shamell.online /etc/nginx/sites-enabled/api.shamell.online
  sudo ln -sfn /etc/nginx/sites-available/media.shamell.online /etc/nginx/sites-enabled/media.shamell.online
  sudo ln -sfn /etc/nginx/sites-available/online.shamell.online /etc/nginx/sites-enabled/online.shamell.online
  sudo ln -sfn /etc/nginx/sites-available/shamell.online /etc/nginx/sites-enabled/shamell.online

  sudo nginx -t
  sudo systemctl reload nginx
  rm -rf '$tmp_remote'
"

echo "Verifying local host route on ${HOST_ALIAS}"
ssh "$HOST_ALIAS" "curl -skfsS -H 'Host: api.shamell.online' https://127.0.0.1/health"

echo "Nginx sync complete."
