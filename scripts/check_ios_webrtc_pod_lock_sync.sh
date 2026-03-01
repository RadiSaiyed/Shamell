#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

lock_file="clients/shamell_flutter/pubspec.lock"
pod_lock_file="clients/shamell_flutter/ios/Podfile.lock"

if [[ ! -f "$lock_file" ]]; then
  echo "[FAIL] missing lock file: $lock_file" >&2
  exit 1
fi
if [[ ! -f "$pod_lock_file" ]]; then
  echo "[FAIL] missing Podfile.lock: $pod_lock_file" >&2
  exit 1
fi

extract_pub_version() {
  local package="$1"
  awk -v pkg="$package" '
    $1==pkg":" {in_block=1; next}
    in_block && $1=="version:" {gsub(/"/,"",$2); print $2; exit}
    in_block && NF==0 {in_block=0}
  ' "$lock_file"
}

webrtc_pkg_version="$(extract_pub_version "flutter_webrtc")"
if [[ -z "${webrtc_pkg_version:-}" ]]; then
  echo "[FAIL] could not parse flutter_webrtc version from $lock_file" >&2
  exit 1
fi

find_webrtc_podspec() {
  local v="$1"
  local candidates=(
    "clients/shamell_flutter/ios/.symlinks/plugins/flutter_webrtc/ios/flutter_webrtc.podspec"
    "$HOME/.pub-cache/hosted/pub.dev/flutter_webrtc-$v/ios/flutter_webrtc.podspec"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

podspec_path="$(find_webrtc_podspec "$webrtc_pkg_version" || true)"
if [[ -z "${podspec_path:-}" ]]; then
  echo "[FAIL] could not locate flutter_webrtc podspec for version $webrtc_pkg_version" >&2
  exit 1
fi

expected_sdk_version="$(
  awk -F"'" '
    /WebRTC-SDK/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "WebRTC-SDK") {
          print $(i + 2)
          exit
        }
      }
    }
  ' "$podspec_path"
)"

if [[ -z "${expected_sdk_version:-}" ]]; then
  echo "[FAIL] could not parse expected WebRTC-SDK version from $podspec_path" >&2
  exit 1
fi

declared_sdk_version="$(
  awk '
    $1=="-"{if($2=="flutter_webrtc"){in_block=1; next}}
    in_block && $1=="-" && $2=="WebRTC-SDK" {
      version=$0
      sub(/^.*WebRTC-SDK \(= /, "", version)
      sub(/\).*/, "", version)
      print version
      exit
    }
    in_block && $1=="-" && $2!="Flutter" && $2!="WebRTC-SDK" {next}
    in_block && NF==0 {in_block=0}
  ' "$pod_lock_file"
)"

resolved_sdk_version="$(
  awk '
    /^  - WebRTC-SDK \(/ {
      version=$0
      sub(/^  - WebRTC-SDK \(/, "", version)
      sub(/\).*/, "", version)
      print version
      exit
    }
  ' "$pod_lock_file"
)"

if [[ -z "${declared_sdk_version:-}" || -z "${resolved_sdk_version:-}" ]]; then
  echo "[FAIL] could not parse WebRTC-SDK versions from $pod_lock_file" >&2
  exit 1
fi

if [[ "$declared_sdk_version" != "$resolved_sdk_version" ]]; then
  echo "[FAIL] Podfile.lock inconsistent: flutter_webrtc declares WebRTC-SDK=$declared_sdk_version but resolved WebRTC-SDK=$resolved_sdk_version" >&2
  exit 1
fi

if [[ "$resolved_sdk_version" != "$expected_sdk_version" ]]; then
  echo "[FAIL] flutter_webrtc/WebRTC-SDK lock mismatch: expected=$expected_sdk_version resolved=$resolved_sdk_version" >&2
  echo "       Action: run 'cd clients/shamell_flutter/ios && pod update WebRTC-SDK && pod install --repo-update' and commit Podfile.lock." >&2
  exit 1
fi

echo "[OK]   iOS flutter_webrtc Pod lock is in sync (flutter_webrtc=$webrtc_pkg_version, WebRTC-SDK=$resolved_sdk_version)"
