#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_app_dir="$repo_root/clients/shamell_flutter/android/app"

placeholder_re='REPLACE_WITH_FIREBASE_API_KEY|000000000000-placeholder|1:000000000000:android:|"project_number": "000000000000"'

# Flavors that REQUIRE a real (non-placeholder) Firebase Android app config.
required_flavors=(user ride driver operator)
# Flavors where Firebase is not yet provisioned. A missing or placeholder
# google-services.json is tolerated (warning, not error). Remove an entry from
# this list once its Firebase Android app is registered for the package name.
optional_flavors=(busOperator hotelOperator)

status=0

echo "Checking Firebase Android flavor configs in $android_app_dir"

package_name_for_flavor() {
  case "$1" in
    user) printf '%s\n' "online.shamell.app" ;;
    ride) printf '%s\n' "online.shamell.ride" ;;
    driver) printf '%s\n' "online.shamell.driver" ;;
    operator) printf '%s\n' "online.shamell.operator" ;;
    busOperator) printf '%s\n' "online.shamell.busoperator" ;;
    hotelOperator) printf '%s\n' "online.shamell.hoteloperator" ;;
    *) return 1 ;;
  esac
}

check_flavor() {
  local flavor="$1"
  local required="$2"
  local package_name
  if ! package_name="$(package_name_for_flavor "$flavor")"; then
    echo "[FAIL] unknown flavor $flavor"
    return 1
  fi
  local config_path="$android_app_dir/src/$flavor/google-services.json"

  if [[ ! -f "$config_path" ]]; then
    if [[ "$required" == "true" ]]; then
      echo "[MISS] $flavor -> $config_path"
      return 1
    fi
    echo "[WARN] $flavor -> $config_path missing (optional, Firebase disabled for this flavor)"
    return 0
  fi

  if grep -Eq "$placeholder_re" "$config_path"; then
    if [[ "$required" == "true" ]]; then
      echo "[FAIL] $flavor -> placeholder values detected in $config_path"
      return 1
    fi
    echo "[WARN] $flavor -> placeholder values in $config_path (optional, Firebase disabled for this flavor)"
    return 0
  fi

  if ! grep -Eq "\"package_name\"[[:space:]]*:[[:space:]]*\"$package_name\"" "$config_path"; then
    echo "[FAIL] $flavor -> expected package_name $package_name in $config_path"
    return 1
  fi

  echo "[OK]   $flavor -> $package_name"
  return 0
}

for flavor in "${required_flavors[@]}"; do
  if ! check_flavor "$flavor" true; then
    status=1
  fi
done

for flavor in "${optional_flavors[@]}"; do
  if ! check_flavor "$flavor" false; then
    status=1
  fi
done

exit "$status"
