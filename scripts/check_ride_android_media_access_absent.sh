#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/check_ride_android_media_access_absent.sh \
    --apk /absolute/path/to/shamell-ride.apk \
    [--out-dir /absolute/path/to/evidence-dir]

Verifies the final Shamell Ride Android APK does not request camera or
microphone access and writes a regulator-friendly evidence bundle:

  - ride-media-access-report.txt
  - ride-media-access-report.json
  - ride-media-access-manifest.xml

Requirements:
  - apkanalyzer
  - a usable Java runtime (apkanalyzer depends on it)
  - python3
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing required command: $1" >&2
    exit 1
  }
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    shasum -a 256 "$path" | awk '{print $1}'
  fi
}

apk_path=""
out_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk)
      apk_path="${2:-}"
      shift 2
      ;;
    --out-dir)
      out_dir="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[FAIL] unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$apk_path" ]]; then
  echo "[FAIL] --apk is required" >&2
  usage >&2
  exit 1
fi

if [[ ! -f "$apk_path" ]]; then
  echo "[FAIL] APK not found: $apk_path" >&2
  exit 1
fi

require_cmd apkanalyzer
require_cmd python3
require_cmd java

if ! java -version >/dev/null 2>&1; then
  echo "[FAIL] Java runtime is installed but not usable; fix JAVA_HOME/JDK setup before running APK evidence checks" >&2
  exit 1
fi

if ! apkanalyzer apk summary "$apk_path" >/dev/null 2>&1; then
  echo "[FAIL] apkanalyzer could not inspect the APK. Ensure Android SDK cmdline-tools and a working JDK are installed." >&2
  exit 1
fi

timestamp_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
if [[ -z "$out_dir" ]]; then
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  out_dir="${repo_root}/.artifacts/regulator-evidence/ride-media-${timestamp_utc//[:]/-}"
fi
mkdir -p "$out_dir"

manifest_xml_path="${out_dir}/ride-media-access-manifest.xml"
report_txt_path="${out_dir}/ride-media-access-report.txt"
report_json_path="${out_dir}/ride-media-access-report.json"

summary="$(apkanalyzer apk summary "$apk_path")"
app_id="$(printf '%s\n' "$summary" | awk '{print $1}')"
version_code="$(printf '%s\n' "$summary" | awk '{print $2}')"
version_name="$(printf '%s\n' "$summary" | cut -d' ' -f3-)"
permissions_raw="$(apkanalyzer manifest permissions "$apk_path" | tr -d '\r')"
features_raw="$(apkanalyzer apk features --not-required "$apk_path" | tr -d '\r')"
manifest_xml="$(apkanalyzer manifest print "$apk_path")"
printf '%s\n' "$manifest_xml" > "$manifest_xml_path"

debuggable="$(
  python3 - "$manifest_xml_path" <<'PY'
import sys
import xml.etree.ElementTree as ET

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"

tree = ET.parse(sys.argv[1])
root = tree.getroot()
app = root.find("application")
if app is None:
    print("unknown")
    raise SystemExit(0)
value = (app.get(f"{ANDROID_NS}debuggable") or "").strip().lower()
if value in {"true", "false"}:
    print(value)
else:
    print("default-false")
PY
)"

sha256="$(sha256_file "$apk_path")"
file_size_bytes="$(wc -c < "$apk_path" | tr -d ' ')"

declare -a prohibited_permissions=(
  "android.permission.CAMERA"
  "android.permission.RECORD_AUDIO"
  "android.permission.MODIFY_AUDIO_SETTINGS"
)
declare -a prohibited_features=(
  "android.hardware.camera"
  "android.hardware.microphone"
)

declare -a found_permissions=()
for permission in "${prohibited_permissions[@]}"; do
  if printf '%s\n' "$permissions_raw" | grep -Fxq "$permission"; then
    found_permissions+=("$permission")
  fi
done

declare -a found_features=()
for feature in "${prohibited_features[@]}"; do
  if printf '%s\n' "$features_raw" | grep -Fq "$feature"; then
    found_features+=("$feature")
  fi
done

verdict="PASS"
declare -a failures=()
if [[ "$app_id" != "online.shamell.ride" ]]; then
  verdict="FAIL"
  failures+=("unexpected application id: $app_id")
fi
if [[ "$debuggable" == "true" ]]; then
  verdict="FAIL"
  failures+=("release APK is debuggable")
fi
if [[ "${#found_permissions[@]}" -gt 0 ]]; then
  verdict="FAIL"
  failures+=("prohibited permissions present: ${found_permissions[*]}")
fi
if [[ "${#found_features[@]}" -gt 0 ]]; then
  verdict="FAIL"
  failures+=("prohibited hardware features present: ${found_features[*]}")
fi

python3 - "$report_json_path" \
  "$timestamp_utc" \
  "$apk_path" \
  "$sha256" \
  "$file_size_bytes" \
  "$app_id" \
  "$version_code" \
  "$version_name" \
  "$debuggable" \
  "$verdict" \
  "$permissions_raw" \
  "$features_raw" \
  "$(printf '%s\n' "${found_permissions[@]-}")" \
  "$(printf '%s\n' "${found_features[@]-}")" \
  "$(printf '%s\n' "${failures[@]-}")" <<'PY'
import json
import sys
from pathlib import Path

payload = {
    "checked_at_utc": sys.argv[2],
    "apk_path": sys.argv[3],
    "sha256": sys.argv[4],
    "file_size_bytes": int(sys.argv[5]),
    "application_id": sys.argv[6],
    "version_code": sys.argv[7],
    "version_name": sys.argv[8],
    "debuggable": sys.argv[9],
    "verdict": sys.argv[10],
    "all_permissions": [line for line in sys.argv[11].splitlines() if line.strip()],
    "all_features": [line for line in sys.argv[12].splitlines() if line.strip()],
    "prohibited_permissions_found": [line for line in sys.argv[13].splitlines() if line.strip()],
    "prohibited_features_found": [line for line in sys.argv[14].splitlines() if line.strip()],
    "failures": [line for line in sys.argv[15].splitlines() if line.strip()],
}
Path(sys.argv[1]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

{
  echo "Shamell Ride Android Media Access Evidence"
  echo "Checked at (UTC): $timestamp_utc"
  echo "APK: $apk_path"
  echo "SHA-256: $sha256"
  echo "Size (bytes): $file_size_bytes"
  echo "Application ID: $app_id"
  echo "Version code: $version_code"
  echo "Version name: $version_name"
  echo "Debuggable: $debuggable"
  echo "Verdict: $verdict"
  echo
  echo "Prohibited permissions checked:"
  printf '  - %s\n' "${prohibited_permissions[@]}"
  echo
  echo "Prohibited features checked:"
  printf '  - %s\n' "${prohibited_features[@]}"
  echo
  echo "Permissions present in APK:"
  if [[ -n "$permissions_raw" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "  - $line"
    done <<< "$permissions_raw"
  else
    echo "  - <none>"
  fi
  echo
  echo "Features present in APK:"
  if [[ -n "$features_raw" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "  - $line"
    done <<< "$features_raw"
  else
    echo "  - <none>"
  fi
  echo
  if [[ "${#failures[@]}" -gt 0 ]]; then
    echo "Failures:"
    printf '  - %s\n' "${failures[@]}"
  else
    echo "Failures:"
    echo "  - <none>"
  fi
  echo
  echo "Generated files:"
  echo "  - $report_txt_path"
  echo "  - $report_json_path"
  echo "  - $manifest_xml_path"
} > "$report_txt_path"

cat "$report_txt_path"

if [[ "$verdict" != "PASS" ]]; then
  exit 1
fi
