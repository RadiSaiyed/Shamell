#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_app_dir="$repo_root/clients/shamell_flutter/android/app"

placeholder_re='REPLACE_WITH_FIREBASE_API_KEY|000000000000-placeholder|1:000000000000:android:|"project_number": "000000000000"'

status=0

echo "Checking Firebase Android flavor configs in $android_app_dir"

for flavor in user ride driver operator; do
  case "$flavor" in
    user) package_name="online.shamell.app" ;;
    ride) package_name="online.shamell.ride" ;;
    driver) package_name="online.shamell.driver" ;;
    operator) package_name="online.shamell.operator" ;;
    *) echo "[FAIL] unknown flavor $flavor"; exit 1 ;;
  esac
  config_path="$android_app_dir/src/$flavor/google-services.json"

  if [[ ! -f "$config_path" ]]; then
    echo "[MISS] $flavor -> $config_path"
    status=1
    continue
  fi

  if rg -q "$placeholder_re" "$config_path"; then
    echo "[FAIL] $flavor -> placeholder values detected in $config_path"
    status=1
    continue
  fi

  if ! rg -q "\"package_name\"[[:space:]]*:[[:space:]]*\"$package_name\"" "$config_path"; then
    echo "[FAIL] $flavor -> expected package_name $package_name in $config_path"
    status=1
    continue
  fi

  echo "[OK]   $flavor -> $package_name"
done

exit "$status"
