#!/usr/bin/env bash
set -euo pipefail

require_prod="${REQUIRE_PRODUCTION_SIGNING:-false}"
allow_debug_signing="${SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING:-false}"
found_release_tls_pins_define=false
found_release_build_args_source=false

if [[ "$require_prod" == "true" && "$allow_debug_signing" == "true" ]]; then
  echo "[FAIL] SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING must be false when REQUIRE_PRODUCTION_SIGNING=true" >&2
  exit 1
fi

decode_base64_csv() {
  local raw="$1"
  if [[ -z "$raw" ]]; then
    return 0
  fi
  python3 - "$raw" <<'PY'
import base64
import sys

raw = sys.argv[1]
for item in raw.split(","):
    item = item.strip()
    if not item:
        continue
    padded = item + "=" * ((4 - len(item) % 4) % 4)
    try:
        print(base64.b64decode(padded).decode("utf-8"), end="\n")
    except Exception:
        print(item, end="\n")
PY
}

is_forbidden_define() {
  local key="$1"
  local value="$2"
  local lower_value
  key="${key// /}"
  value="${value// /}"
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$key" in
    ALLOW_LEGACY_SESSION_FALLBACK_ON_MOBILE_IN_RELEASE|ALLOW_LEGACY_SESSION_FALLBACK_IN_RELEASE)
      [[ "$lower_value" == "true" ]]
      ;;
    ENABLE_MOBILE_SECURE_STORAGE|ENABLE_DESKTOP_SECURE_STORAGE)
      [[ "$lower_value" == "false" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

is_forbidden_release_network_define() {
  local key="$1"
  local value="$2"
  local lower_value
  if [[ "$require_prod" != "true" ]]; then
    return 1
  fi
  key="${key// /}"
  value="${value// /}"
  lower_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$key" in
    BASE_URL|TRUSTED_API_ORIGINS)
      [[ "$lower_value" == *"http://"* ]] && return 0
      [[ "$lower_value" == *"localhost"* ]] && return 0
      [[ "$lower_value" == *"127.0.0.1"* ]] && return 0
      [[ "$lower_value" == *"::1"* ]] && return 0
      [[ "$lower_value" == *".local"* ]] && return 0
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

validate_release_tls_pins_define() {
  local value="$1"
  python3 - "$value" <<'PY'
import base64
import sys

raw = sys.argv[1].strip()
entries = [entry.strip() for entry in raw.split(";") if entry.strip()]
if not entries:
    raise SystemExit("release TLS pin bundle is empty")
for index, entry in enumerate(entries, start=1):
    try:
        decoded = base64.b64decode(entry + "=" * ((4 - len(entry) % 4) % 4), validate=True)
    except Exception as exc:
        raise SystemExit(f"release TLS pin #{index} is not valid base64: {exc}")
    if len(decoded) < 64:
        raise SystemExit(f"release TLS pin #{index} is too short to be a DER certificate")
PY
}

check_define_line() {
  local source_name="$1"
  local line="$2"
  line="$(printf '%s' "$line" | tr -d '\r' | xargs)"
  [[ -z "$line" ]] && return 0

  if [[ "$line" == --dart-define=* ]]; then
    line="${line#--dart-define=}"
  fi
  if [[ "$line" != *=* ]]; then
    return 0
  fi

  local key="${line%%=*}"
  local value="${line#*=}"
  if [[ "$key" == "TRUSTED_TLS_CERTIFICATES_DER_BASE64" ]]; then
    found_release_tls_pins_define=true
    if [[ "$require_prod" == "true" ]]; then
      if ! validate_release_tls_pins_define "$value"; then
        echo "[FAIL] invalid production TLS pin define in ${source_name}: ${key}" >&2
        exit 1
      fi
    fi
  fi
  if is_forbidden_define "$key" "$value"; then
    echo "[FAIL] forbidden release define in ${source_name}: ${key}=${value}" >&2
    exit 1
  fi
  if is_forbidden_release_network_define "$key" "$value"; then
    echo "[FAIL] forbidden production network define in ${source_name}: ${key}=${value}" >&2
    exit 1
  fi
}

check_text_source() {
  local source_name="$1"
  local raw="$2"
  [[ -z "$raw" ]] && return 0
  while IFS= read -r line; do
    check_define_line "$source_name" "$line"
  done <<<"$raw"
}

check_args_source() {
  local source_name="$1"
  local raw="$2"
  [[ -z "$raw" ]] && return 0
  python3 - "$raw" <<'PY' | while IFS= read -r token; do
import shlex
import sys

for token in shlex.split(sys.argv[1]):
    print(token)
PY
    check_define_line "$source_name" "$token"
  done
}

check_release_build_hardening_source() {
  local source_name="$1"
  local raw="$2"
  [[ -z "$raw" ]] && return 0
  found_release_build_args_source=true
  if [[ "$require_prod" != "true" ]]; then
    return 0
  fi
  python3 - "$source_name" "$raw" <<'PY'
import shlex
import sys

source = sys.argv[1]
raw = sys.argv[2]
tokens = shlex.split(raw)
has_obfuscate = False
has_split_debug_info = False
i = 0
while i < len(tokens):
    token = tokens[i]
    if token == "--obfuscate":
        has_obfuscate = True
    elif token.startswith("--split-debug-info="):
        has_split_debug_info = bool(token.split("=", 1)[1].strip())
    elif token == "--split-debug-info":
        next_index = i + 1
        if next_index >= len(tokens):
            raise SystemExit(
                f"[FAIL] production mobile release build args in {source} "
                "must provide a value for --split-debug-info"
            )
        next_token = tokens[next_index].strip()
        if not next_token or next_token.startswith("--"):
            raise SystemExit(
                f"[FAIL] production mobile release build args in {source} "
                "must provide a non-empty value for --split-debug-info"
            )
        has_split_debug_info = True
        i += 1
    i += 1

if not has_obfuscate:
    raise SystemExit(
        f"[FAIL] production mobile release build args in {source} must include --obfuscate"
    )
if not has_split_debug_info:
    raise SystemExit(
        f"[FAIL] production mobile release build args in {source} must include "
        "--split-debug-info=<dir>"
    )
PY
}

check_text_source "SHAMELL_EXTRA_DART_DEFINES" "${SHAMELL_EXTRA_DART_DEFINES:-}"
check_text_source "EXTRA_DART_DEFINES" "${EXTRA_DART_DEFINES:-}"
check_text_source "FLUTTER_BUILD_DART_DEFINES" "${FLUTTER_BUILD_DART_DEFINES:-}"
check_text_source "DART_DEFINES(decoded)" "$(decode_base64_csv "${DART_DEFINES:-}")"

check_args_source "FLUTTER_BUILD_ARGS" "${FLUTTER_BUILD_ARGS:-}"
check_args_source "EXTRA_FLUTTER_BUILD_ARGS" "${EXTRA_FLUTTER_BUILD_ARGS:-}"
check_args_source "FASTLANE_FLUTTER_BUILD_ARGS" "${FASTLANE_FLUTTER_BUILD_ARGS:-}"

check_release_build_hardening_source "FLUTTER_BUILD_ARGS" "${FLUTTER_BUILD_ARGS:-}"
check_release_build_hardening_source "EXTRA_FLUTTER_BUILD_ARGS" "${EXTRA_FLUTTER_BUILD_ARGS:-}"
check_release_build_hardening_source "FASTLANE_FLUTTER_BUILD_ARGS" "${FASTLANE_FLUTTER_BUILD_ARGS:-}"

if [[ "$require_prod" == "true" && "$found_release_tls_pins_define" != "true" ]]; then
  echo "[FAIL] production-signed mobile releases must set TRUSTED_TLS_CERTIFICATES_DER_BASE64" >&2
  exit 1
fi

if [[ "$require_prod" == "true" && "$found_release_build_args_source" != "true" ]]; then
  echo "[FAIL] production-signed mobile releases must expose flutter build args via FLUTTER_BUILD_ARGS, EXTRA_FLUTTER_BUILD_ARGS, or FASTLANE_FLUTTER_BUILD_ARGS" >&2
  exit 1
fi

echo "[OK]   mobile release security env is fail-closed"
