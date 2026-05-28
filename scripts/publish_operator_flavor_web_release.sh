#!/usr/bin/env bash
set -euo pipefail

# Publish a built operator-flavor web bundle to its dedicated path
# under /var/www/shamell/<slug>/, which is served as
# https://shamell.online/<slug>/ by the catch-all nginx vhost.
#
# Sibling to publish_control_web_release.sh; uses the same retention
# pattern (keep-N newest archives, default 2) so a series of releases
# can't fill the host disk (see the Android-APK incident, 2026-05-28).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR=""
HOST_ALIAS="shamell"
SLUG=""
REMOTE_SUDO_PASSWORD="${REMOTE_SUDO_PASSWORD:-}"
WEB_RELEASES_KEEP="${WEB_RELEASES_KEEP:-2}"
remote_sudo_password_b64=""

usage() {
  cat <<'EOF'
Usage: scripts/publish_operator_flavor_web_release.sh \
    --source-dir DIR --slug SLUG [--host shamell]

Required:
  --source-dir DIR   Directory containing the built bundle
                     (must have index.html + release-manifest.json).
  --slug SLUG        URL/disk slug under /var/www/shamell/, e.g.
                     `carrier`, `bus-control`, `hotels-admin`, `taxi-control`.

Optional:
  --host ALIAS       SSH host alias (default: shamell)

Env:
  REMOTE_SUDO_PASSWORD   If set, used over sudo -S for elevated
                         operations. Otherwise passwordless sudo is
                         assumed (workflow runner config).
  WEB_RELEASES_KEEP      Newest N archives to retain under
                         /var/www/shamell/<slug>/releases/ (default 2).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir) SOURCE_DIR="$2"; shift 2 ;;
    --host) HOST_ALIAS="$2"; shift 2 ;;
    --slug) SLUG="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$SOURCE_DIR" ]]; then
  echo "--source-dir is required" >&2; usage >&2; exit 1
fi
if [[ -z "$SLUG" ]]; then
  echo "--slug is required" >&2; usage >&2; exit 1
fi
# Defensive: slug ends up in shell-expanded paths, so we lock it to a
# narrow charset to keep operator quoting honest.
if ! [[ "$SLUG" =~ ^[a-z][a-z0-9-]{1,32}$ ]]; then
  echo "--slug must match [a-z][a-z0-9-]{1,32}: $SLUG" >&2
  exit 1
fi
REMOTE_ROOT="/var/www/shamell/${SLUG}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2; exit 1
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

tmp_remote="/tmp/shamell-${SLUG}-web-publish-$$"
release_root="${REMOTE_ROOT}/releases/${release_id}"

echo "Copying ${SLUG} web bundle to ${HOST_ALIAS}:${tmp_remote}"
ssh "$HOST_ALIAS" "rm -rf '$tmp_remote' && mkdir -p '$tmp_remote'"
COPYFILE_DISABLE=1 tar -C "$SOURCE_DIR" \
  --exclude '.DS_Store' \
  --exclude '._*' \
  -cf - . | ssh "$HOST_ALIAS" "tar -xf - -C '$tmp_remote'"

echo "Installing ${SLUG} web bundle on ${HOST_ALIAS}"
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

# Prune historical release archives — keep only the N newest. Each
# Flutter web bundle is ~3 MB, so the disk pressure is lower than
# the Android-APK case, but the same retention discipline applies
# so a runaway publish loop can never starve the host.
releases_keep='${WEB_RELEASES_KEEP}'
sudo_run bash -c "ls -1 '${REMOTE_ROOT}/releases' 2>/dev/null \\
  | grep -v '^${release_id}\$' \\
  | sort -r \\
  | tail -n +\$releases_keep \\
  | while IFS= read -r old; do
      [ -n \"\\\$old\" ] || continue
      rm -rf '${REMOTE_ROOT}/releases/'\\\$old
      echo \"pruned old release archive: \\\$old\"
    done"

sudo_run find '${REMOTE_ROOT}' -mindepth 1 -maxdepth 1 ! -name releases -exec rm -rf {} +
sudo_run cp -a '${tmp_remote}/.' '${REMOTE_ROOT}/'
sudo_run cp -a '${tmp_remote}/.' '${release_root}/'
sudo_run nginx -t
sudo_run systemctl reload nginx
# Best-effort smoke checks: bundle is live the instant cp completes,
# these are confirmation rather than a gate.
curl -skfsS -H 'Host: shamell.online' https://127.0.0.1/${SLUG}/ >/dev/null || true
curl -skfsS -H 'Host: shamell.online' https://127.0.0.1/${SLUG}/release-manifest.json >/dev/null || true
rm -rf '${tmp_remote}'
# Force a clean shell exit so an SSH -tt PTY teardown can't trip the
# job with "Broken pipe" exit 255 after all the publish work is done.
exit 0
EOF

printf 'Published %s web bundle: https://shamell.online/%s/ (%s)\n' "$SLUG" "$SLUG" "$release_id"
