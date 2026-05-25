#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "[FAIL] missing required command: rg" >&2
  exit 1
fi

deps_file="clients/shamell_flutter/.flutter-plugins-dependencies"
registrant_file="clients/shamell_flutter/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"

if [[ ! -f "$deps_file" ]]; then
  echo "[FAIL] missing $deps_file (run flutter pub get in clients/shamell_flutter)" >&2
  exit 1
fi

deps_json="$(tr -d '\n' < "$deps_file")"
android_plugins_block="$(printf '%s' "$deps_json" | sed -E 's/.*"android":\[(.*)\],"macos".*/\1/')"

if [[ -z "$android_plugins_block" || "$android_plugins_block" == "$deps_json" ]]; then
  echo "[FAIL] could not parse android plugin block from $deps_file" >&2
  exit 1
fi

android_dev_plugins=()
while IFS= read -r plugin; do
  [[ -z "$plugin" ]] && continue
  android_dev_plugins+=("$plugin")
done < <(
  printf '%s' "$android_plugins_block" \
    | rg -o '"name":"[^"]+","path":"[^"]+","native_build":true,[^}]*"dev_dependency":true' \
    | sed -E 's/.*"name":"([^"]+)".*/\1/' \
    | sort -u
)

if [[ "${#android_dev_plugins[@]}" -ne 0 ]]; then
  echo "[FAIL] android native plugins must not be dev dependencies:" >&2
  for plugin in "${android_dev_plugins[@]}"; do
    echo "  - $plugin" >&2
  done
  exit 1
fi

registrant_plugins=()
if [[ -f "$registrant_file" ]]; then
  while IFS= read -r plugin; do
    [[ -z "$plugin" ]] && continue
    registrant_plugins+=("$plugin")
  done < <(
    rg -o 'Error registering plugin [^,]+' "$registrant_file" \
      | sed -E 's/.*plugin ([^,]+)$/\1/' \
      | sort -u
  )
fi

errors=0
for plugin in "${registrant_plugins[@]}"; do
  if ! printf '%s' "$android_plugins_block" | rg -q "\"name\":\"$plugin\"[^}]*\"dev_dependency\":false"; then
    echo "[FAIL] Android runtime registrant includes non-runtime plugin '$plugin'" >&2
    rg -n --fixed-strings "$plugin" "$registrant_file" >&2 || true
    errors=1
  fi
done

if (( errors != 0 )); then
  echo "[FAIL] Android plugin registrant/runtime dependency guard failed" >&2
  exit 1
fi

if [[ "${#registrant_plugins[@]}" -eq 0 ]]; then
  echo "[OK]   android plugin list has no dev-only native plugins"
else
  echo "[OK]   android plugin list is clean and registrant references only runtime plugins"
fi
