#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "[FAIL] missing required command: rg" >&2
  exit 1
fi

settings_file="clients/shamell_flutter/android/settings.gradle.kts"
lock_file="clients/shamell_flutter/pubspec.lock"

if [[ ! -f "$settings_file" || ! -f "$lock_file" ]]; then
  echo "[FAIL] missing Kotlin/pub lock inputs for compatibility check" >&2
  exit 1
fi

kgp_version="$(
  rg -n 'org\.jetbrains\.kotlin\.android"\) version "' "$settings_file" \
    | sed -E 's/.*version "([^"]+)".*/\1/' \
    | head -n1
)"

if [[ -z "${kgp_version:-}" ]]; then
  echo "[FAIL] could not parse Kotlin Gradle Plugin version from $settings_file" >&2
  exit 1
fi

webrtc_version="$(
  awk '
    $1=="flutter_webrtc:" {in_block=1; next}
    in_block && $1=="version:" {gsub(/"/,"",$2); print $2; exit}
    in_block && NF==0 {in_block=0}
  ' "$lock_file"
)"

if [[ -z "${webrtc_version:-}" ]]; then
  echo "[FAIL] could not parse flutter_webrtc version from $lock_file" >&2
  exit 1
fi

kgp_major="${kgp_version%%.*}"
kgp_minor_patch="${kgp_version#*.}"
kgp_minor="${kgp_minor_patch%%.*}"

webrtc_major="${webrtc_version%%.*}"
webrtc_minor_patch="${webrtc_version#*.}"
webrtc_minor="${webrtc_minor_patch%%.*}"
webrtc_patch="${webrtc_version##*.}"

# Known blocker (2026-03-01): flutter_webrtc <= 1.3.1 ships an Android
# buildscript pinned to old Kotlin/AGP internals and fails under KGP >= 2.1.
if (( kgp_major > 2 || (kgp_major == 2 && kgp_minor >= 1) )); then
  if (( webrtc_major < 1 )) || (( webrtc_major == 1 && webrtc_minor < 3 )) || \
     (( webrtc_major == 1 && webrtc_minor == 3 && webrtc_patch <= 1 )); then
    echo "[FAIL] KGP $kgp_version is incompatible with flutter_webrtc $webrtc_version" >&2
    echo "       Action: keep KGP at 2.0.x or upgrade flutter_webrtc beyond 1.3.1 first." >&2
    exit 1
  fi
fi

echo "[OK]   Kotlin/flutter_webrtc compatibility check passed (KGP=$kgp_version, flutter_webrtc=$webrtc_version)"
