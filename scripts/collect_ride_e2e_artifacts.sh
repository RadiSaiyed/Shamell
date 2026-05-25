#!/usr/bin/env bash
set -euo pipefail

DEST_DIR="${1:-.artifacts/ride-e2e-latest}"

mkdir -p "$DEST_DIR"

latest_dir="$(ls -dt /tmp/shamell-ride-e2e-* 2>/dev/null | head -n1 || true)"
if [[ -z "$latest_dir" || ! -d "$latest_dir" ]]; then
  echo "No /tmp/shamell-ride-e2e-* directory found." > "${DEST_DIR}/missing.txt"
  exit 0
fi

run_name="$(basename "$latest_dir")"
target_dir="${DEST_DIR}/${run_name}"
rm -rf "$target_dir"
mkdir -p "$target_dir"
cp -R "${latest_dir}/." "$target_dir/"
printf '%s\n' "$latest_dir" > "${DEST_DIR}/source_path.txt"
printf '%s\n' "$run_name" > "${DEST_DIR}/latest_run.txt"
