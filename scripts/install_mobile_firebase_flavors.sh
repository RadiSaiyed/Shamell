#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_app_dir="$repo_root/clients/shamell_flutter/android/app"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/install_mobile_firebase_flavors.sh /absolute/path/to/firebase-config-dir

Expected source files:
  user.google-services.json
  ride.google-services.json
  driver.google-services.json
  operator.google-services.json

The script validates each file against the expected Android package name and
copies it into the ignored local flavor path under:
  clients/shamell_flutter/android/app/src/<flavor>/google-services.json

Validation only:
  bash scripts/check_mobile_firebase_flavors.sh
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 64
fi

source_dir="$1"
if [[ ! -d "$source_dir" ]]; then
  echo "[FAIL] source directory not found: $source_dir" >&2
  exit 1
fi

placeholder_re='REPLACE_WITH_FIREBASE_API_KEY|000000000000-placeholder|1:000000000000:android:|"project_number": "000000000000"'

expected_package_name() {
  case "$1" in
    user) echo "online.shamell.app" ;;
    ride) echo "online.shamell.ride" ;;
    driver) echo "online.shamell.driver" ;;
    operator) echo "online.shamell.operator" ;;
    *) return 1 ;;
  esac
}

for flavor in user ride driver operator; do
  src="$source_dir/$flavor.google-services.json"
  dst_dir="$android_app_dir/src/$flavor"
  dst="$dst_dir/google-services.json"
  package_name="$(expected_package_name "$flavor")"

  if [[ ! -f "$src" ]]; then
    echo "[FAIL] missing source file for $flavor: $src" >&2
    exit 1
  fi

  if rg -q "$placeholder_re" "$src"; then
    echo "[FAIL] placeholder values detected in $src" >&2
    exit 1
  fi

  if ! rg -q "\"package_name\"[[:space:]]*:[[:space:]]*\"$package_name\"" "$src"; then
    echo "[FAIL] expected package_name $package_name in $src" >&2
    exit 1
  fi

  mkdir -p "$dst_dir"
  cp "$src" "$dst"
  echo "[OK] installed $flavor -> $dst"
done

echo
echo "Installed Android Firebase flavor configs."
echo "Next: bash scripts/check_mobile_firebase_flavors.sh"
