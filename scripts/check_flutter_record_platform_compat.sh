#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

lock_file="clients/shamell_flutter/pubspec.lock"

if [[ ! -f "$lock_file" ]]; then
  echo "[FAIL] missing lock file: $lock_file" >&2
  exit 1
fi

extract_version() {
  local package="$1"
  awk -v pkg="$package" '
    $1==pkg":" {in_block=1; next}
    in_block && $1=="version:" {gsub(/"/,"",$2); print $2; exit}
    in_block && NF==0 {in_block=0}
  ' "$lock_file"
}

version_ge() {
  local a="$1"
  local b="$2"
  # Returns true if a >= b (semantic-like, dot-separated numeric parts).
  if [[ "$a" == "$b" ]]; then
    return 0
  fi
  local IFS=.
  local i
  read -r -a av <<< "$a"
  read -r -a bv <<< "$b"
  local max_len="${#av[@]}"
  if (( ${#bv[@]} > max_len )); then
    max_len="${#bv[@]}"
  fi
  for (( i=0; i<max_len; i++ )); do
    local ai="${av[i]:-0}"
    local bi="${bv[i]:-0}"
    if (( ai > bi )); then
      return 0
    fi
    if (( ai < bi )); then
      return 1
    fi
  done
  return 0
}

record_version="$(extract_version "record")"
record_platform_version="$(extract_version "record_platform_interface")"
record_linux_version="$(extract_version "record_linux")"

if [[ -z "${record_version:-}" ]]; then
  echo "[FAIL] could not parse 'record' version from $lock_file" >&2
  exit 1
fi
if [[ -z "${record_platform_version:-}" ]]; then
  echo "[FAIL] could not parse 'record_platform_interface' version from $lock_file" >&2
  exit 1
fi

# Known compatibility floor after upgrading to record 6.2.0+:
# record_platform_interface 1.5.0 changed hasPermission signature;
# record_linux must be 1.3.0+ to match it.
if version_ge "$record_version" "6.2.0" && version_ge "$record_platform_version" "1.5.0"; then
  if [[ -z "${record_linux_version:-}" ]]; then
    echo "[FAIL] record_linux missing while record=$record_version and record_platform_interface=$record_platform_version" >&2
    exit 1
  fi
  if ! version_ge "$record_linux_version" "1.3.0"; then
    echo "[FAIL] incompatible record stack: record=$record_version, record_platform_interface=$record_platform_version, record_linux=$record_linux_version" >&2
    echo "       Action: upgrade record_linux to >=1.3.0 (or downgrade record stack consistently)." >&2
    exit 1
  fi
fi

echo "[OK]   Flutter record platform compatibility check passed (record=$record_version, record_platform_interface=$record_platform_version, record_linux=${record_linux_version:-n/a})"
