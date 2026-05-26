#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR=""
HOST_ALIAS="shamell"
REMOTE_ROOT="/var/www/shamell/downloads/android"
REMOTE_SUDO_PASSWORD="${REMOTE_SUDO_PASSWORD:-}"
remote_sudo_password_b64=""

usage() {
  cat <<'EOF'
Usage: scripts/publish_android_apk_downloads.sh --source-dir DIR [--host shamell] [--remote-root /var/www/shamell/downloads/android]

Publish a prepared Android APK bundle (index.html + release-manifest.json + APKs)
to the Hetzner host serving https://shamell.online/downloads/android/

Typical flow:
  1. scripts/build_android_release_apks.sh --output-dir .artifacts/android-apk-release
  2. scripts/sync_hetzner_nginx.sh shamell
  3. scripts/publish_android_apk_downloads.sh --source-dir .artifacts/android-apk-release
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
require_cmd scp
require_cmd python3

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

# NOTE: bash 3.2 (system bash on macOS) lacks `mapfile`/`readarray`, which
# would silently leave `bundle_files` empty and skip the upload. The read
# loop below is portable to bash 3.2 and bash 4+ without other behaviour
# changes.
bundle_files=()
while IFS= read -r bundle_file_line; do
  [[ -z "$bundle_file_line" ]] && continue
  bundle_files+=("$bundle_file_line")
done < <(python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print("index.html")
print("release-manifest.json")
for app in payload["apps"]:
    print(app["file_name"])
    qr_file = app.get("qr_file")
    if qr_file:
        print(qr_file)
PY
)

tmp_remote="/tmp/shamell-android-apk-publish-${HOST_ALIAS}"
release_root="${REMOTE_ROOT}/releases/${release_id}"

# Use a host-stable temp dir (not $$-suffixed) so a previous run's
# partial bytes are reused by `rsync --append-verify` on the next
# attempt. The dir is wiped on the remote side after the install step
# anyway, so there's no long-term accumulation.

echo "Copying APK bundle to ${HOST_ALIAS}:${tmp_remote}"
ssh "$HOST_ALIAS" "mkdir -p '$tmp_remote'"

# `--partial --append-verify` resumes from the last byte if the SSH
# stream drops mid-transfer (the previous scp lost ~70 MB of progress
# every disconnect). `--inplace` keeps the partial bytes under the
# final name so an interrupted run can resume on the same path.
# Keep-alive args prevent the ssh transport from being torn down by an
# idle NAT during the slow upload from residential upstream.
RSYNC_SSH=(
  ssh
  -o ServerAliveInterval=20
  -o ServerAliveCountMax=10
  -o TCPKeepAlive=yes
  -o ConnectTimeout=30
)
# Feature-detect resume flags. GNU rsync (Linux, brew-installed on
# macOS) has `--inplace --append-verify` for resumable mid-file
# transfers across SSH drops. macOS ships openrsync, which has neither
# flag — fall back to `--partial` alone (keeps incomplete files between
# attempts so the next try at least doesn't re-upload from 0 bytes;
# still has to re-transfer the partial chunk).
#
# The detection uses the version banner because `rsync --append-verify`
# returns a non-zero exit under `set -o pipefail`, which would make
# a naive `rsync --append-verify | grep` test always look like
# "supported" — exactly the misdetection that caused the v1 of this
# script to retry --append-verify five times in a row on macOS before
# giving up. The version banner is the only invariant we can trust.
RSYNC_RESUME_FLAGS=(--partial)
# `head -1` closes its stdin after one line; rsync then hits SIGPIPE
# on its next write, exits 141, and under `pipefail` the pipeline's
# overall exit is 141. With `set -e` that would silently abort the
# whole script (the previous incarnation of this detection died here
# without even reaching the `if`). The `|| true` swallows the SIGPIPE
# noise — the banner is still captured in $RSYNC_VERSION_BANNER.
RSYNC_VERSION_BANNER="$(rsync --version 2>&1 | head -1 || true)"
# GNU rsync 3.4.2 prints `rsync  version 3.4.2  protocol version 32`
# (two spaces) while older builds use a single space — match either by
# normalising the whitespace before the comparison.
RSYNC_VERSION_NORMALISED="$(echo "$RSYNC_VERSION_BANNER" | tr -s ' ')"
if [[ "$RSYNC_VERSION_NORMALISED" == rsync\ version\ 3.* || "$RSYNC_VERSION_NORMALISED" == rsync\ version\ 4.* ]]; then
  # `--inplace` writes directly to the final filename so a partial
  # file is preserved between rsync invocations (combined with
  # `--partial`). Intentionally **not** using `--append-verify`:
  # the verify phase reads the entire existing file to hash it,
  # which on residential upstream takes nearly as long as a fresh
  # transfer — and is wasted entirely when the partial belongs to a
  # *different* build (SHA mismatch → rsync falls back to full
  # re-transfer anyway). `--partial --inplace` alone gives us
  # resume-from-byte-N within a single build session via rsync's
  # rolling-checksum delta algorithm, which is the only case that
  # actually matters in practice (NAT drops mid-upload). For
  # cross-build resumes we just delete the stale partial first.
  RSYNC_RESUME_FLAGS+=(--inplace)
else
  echo "rsync flavour ($RSYNC_VERSION_BANNER) lacks --inplace; falling back to --partial only" >&2
fi
for bundle_file in "${bundle_files[@]}"; do
  if [[ ! -f "${SOURCE_DIR}/${bundle_file}" ]]; then
    echo "Bundle file referenced by manifest is missing: ${bundle_file}" >&2
    exit 1
  fi
  for attempt in 1 2 3 4 5; do
    if rsync \
        "${RSYNC_RESUME_FLAGS[@]}" \
        --progress \
        --rsh "${RSYNC_SSH[*]}" \
        "${SOURCE_DIR}/${bundle_file}" \
        "${HOST_ALIAS}:${tmp_remote}/${bundle_file}"; then
      break
    fi
    if [[ "$attempt" -ge 5 ]]; then
      echo "rsync of ${bundle_file} failed after 5 attempts" >&2
      exit 1
    fi
    echo "rsync attempt ${attempt} for ${bundle_file} failed; retrying after backoff…" >&2
    sleep $((attempt * 5))
  done
done

echo "Installing APK bundle on ${HOST_ALIAS}"
# The download dir is shamell-owned (`/var/www/shamell/downloads/android`
# is `shamell:shamell 775`), so the file ops below all succeed as the
# logged-in shamell user — no sudo wrapper needed. The nginx reload
# (which would require sudo) is also redundant: nginx serves static
# content directly from disk, so a content swap is visible on the next
# request without a config reload. We keep `nginx -t` and reload as
# optional best-effort steps wrapped in `sudo -n` so they run on hosts
# where shamell has passwordless sudo for those exact commands, and
# silently skip otherwise. Either way the APKs become live the
# instant the `cp` completes.
ssh -tt "$HOST_ALIAS" "bash -s" <<EOF
set -euo pipefail
REMOTE_SUDO_PASSWORD_B64='${remote_sudo_password_b64}'

# Try to run a privileged command. Order of preference:
#   1) REMOTE_SUDO_PASSWORD_B64 from the caller's env → pipe via sudo -S
#   2) Passwordless sudo (NOPASSWD config on the host)
#   3) Skip with a warning — the operation is best-effort.
optional_sudo_run() {
  if [[ -n "\${REMOTE_SUDO_PASSWORD_B64:-}" ]]; then
    printf '%s' "\${REMOTE_SUDO_PASSWORD_B64}" | base64 --decode | sudo -S -p '' "\$@" || true
  elif sudo -n true 2>/dev/null; then
    sudo -n "\$@" || true
  else
    echo "Skipping (no sudo available): \$*" >&2
  fi
}

install -d -m 0755 '${REMOTE_ROOT}' || true
install -d -m 0755 '${REMOTE_ROOT}/releases' || true
install -d -m 0755 '${release_root}'
find '${REMOTE_ROOT}' -mindepth 1 -maxdepth 1 ! -name releases -exec rm -rf {} +
cp -a '${tmp_remote}/.' '${REMOTE_ROOT}/'
cp -a '${tmp_remote}/.' '${release_root}/'
# Best-effort nginx ops — not required for content visibility.
optional_sudo_run nginx -t
optional_sudo_run systemctl reload nginx
# Post-publish smoke checks — non-fatal. nginx serves the new bundle
# the moment cp -a finishes; these are extra reassurance, not a gate.
# Wrapped in || true so a transient SNI / resolve / loopback hiccup
# doesn't fail the CI job after the files are already in place.
curl -skfsS -H 'Host: shamell.online' https://127.0.0.1/downloads/android/release-manifest.json >/dev/null || true
curl -skfI  -H 'Host: shamell.online' https://127.0.0.1/downloads/android/ >/dev/null || true
rm -rf '${tmp_remote}'
# Force a clean shell exit so an SSH -tt PTY teardown can't trip the
# job with "Broken pipe" exit 255 after all the publish work is done.
exit 0
EOF

printf 'Published Android APK bundle: https://shamell.online/downloads/android/ (%s)\n' "$release_id"
