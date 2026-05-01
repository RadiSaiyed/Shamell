#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR=""
HOST_ALIAS="shamell"
REMOTE_ROOT="/var/www/shamell/control"
REMOTE_SUDO_PASSWORD="${REMOTE_SUDO_PASSWORD:-}"
remote_sudo_password_b64=""

usage() {
  cat <<'EOF'
Usage: scripts/publish_control_web_release.sh --source-dir DIR [--host shamell] [--remote-root /var/www/shamell/control]

Publish a prepared Shamell Control web bundle to:
  https://shamell.online/control/

Typical flow:
  1. scripts/build_control_web_release.sh --output-dir .artifacts/control-web-release
  2. scripts/sync_hetzner_nginx.sh shamell
  3. scripts/publish_control_web_release.sh --source-dir .artifacts/control-web-release
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      SOURCE_DIR="$2"
      shift 2
      ;;
    --host)
      HOST_ALIAS="$2"
      shift 2
      ;;
    --remote-root)
      REMOTE_ROOT="$2"
      shift 2
      ;;
    -h|--help)
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

if [[ -z "$SOURCE_DIR" ]]; then
  echo "--source-dir is required" >&2
  usage >&2
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd ssh
require_cmd python3
require_cmd tar

if [[ -n "${REMOTE_SUDO_PASSWORD}" ]]; then
  remote_sudo_password_b64="$(printf '%s' "${REMOTE_SUDO_PASSWORD}" | base64 | tr -d '\n')"
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
MANIFEST_PATH="${SOURCE_DIR}/release-manifest.json"
INDEX_PATH="${SOURCE_DIR}/index.html"

if [[ ! -f "$MANIFEST_PATH" || ! -f "$INDEX_PATH" ]]; then
  echo "Source bundle must contain index.html and release-manifest.json: $SOURCE_DIR" >&2
  exit 1
fi

release_id="$(python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(payload["release_id"])
PY
)"

tmp_remote="/tmp/shamell-control-web-publish-$$"
release_root="${REMOTE_ROOT}/releases/${release_id}"

echo "Copying Shamell Control web bundle to ${HOST_ALIAS}:${tmp_remote}"
ssh "$HOST_ALIAS" "rm -rf '$tmp_remote' && mkdir -p '$tmp_remote'"
COPYFILE_DISABLE=1 tar -C "$SOURCE_DIR" \
  --exclude '.DS_Store' \
  --exclude '._*' \
  -cf - . | ssh "$HOST_ALIAS" "tar -xf - -C '$tmp_remote'"

echo "Installing Shamell Control web bundle on ${HOST_ALIAS}"
ssh_args=()
if [[ -z "${remote_sudo_password_b64}" ]]; then
  ssh_args+=(-tt)
fi
ssh "${ssh_args[@]}" "$HOST_ALIAS" "bash -s" <<EOF
set -euo pipefail
REMOTE_SUDO_PASSWORD_B64='${remote_sudo_password_b64}'

sudo_run() {
  if [[ -n "\${REMOTE_SUDO_PASSWORD_B64:-}" ]]; then
    printf '%s' "\${REMOTE_SUDO_PASSWORD_B64}" | base64 --decode | sudo -S -p '' "\$@"
  else
    sudo "\$@"
  fi
}

sudo_run install -d -m 0755 /var/www/shamell
sudo_run install -d -m 0755 '${REMOTE_ROOT}'
sudo_run install -d -m 0755 '${REMOTE_ROOT}/releases'
sudo_run install -d -m 0755 '${release_root}'
sudo_run find '${REMOTE_ROOT}' -mindepth 1 -maxdepth 1 ! -name releases -exec rm -rf {} +
sudo_run cp -a '${tmp_remote}/.' '${REMOTE_ROOT}/'
sudo_run cp -a '${tmp_remote}/.' '${release_root}/'
sudo_run nginx -t
sudo_run systemctl reload nginx
curl -skfsS -H 'Host: shamell.online' https://127.0.0.1/control/ >/dev/null
curl -skfsS -H 'Host: shamell.online' https://127.0.0.1/control/release-manifest.json >/dev/null
rm -rf '${tmp_remote}'
EOF

printf 'Published Shamell Control web bundle: https://shamell.online/control/ (%s)\n' "$release_id"
