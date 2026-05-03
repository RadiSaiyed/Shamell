#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_LINK_HOST="${SHAMELL_APP_LINK_HOST:-online.shamell.online}"
IOS_TEAM_ID="${SHAMELL_IOS_TEAM_ID:-AVKQ9VZ94G}"
IOS_BUNDLE_ID="${SHAMELL_IOS_BUNDLE_ID:-online.shamell.app}"
ANDROID_PACKAGE_NAME="${SHAMELL_ANDROID_PACKAGE_NAME:-online.shamell.app}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/ops/hetzner/www/${APP_LINK_HOST}/.well-known}"

tmp_keystore=""

cleanup() {
  if [[ -n "$tmp_keystore" && -f "$tmp_keystore" ]]; then
    rm -f "$tmp_keystore"
  fi
}

trap cleanup EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

resolve_keytool() {
  local candidate=""

  if [[ -n "${KEYTOOL:-}" && -x "${KEYTOOL:-}" ]]; then
    candidate="${KEYTOOL}"
    if "$candidate" -help >/dev/null 2>&1; then
      printf "%s" "$candidate"
      return
    fi
  fi

  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/keytool" ]]; then
    candidate="${JAVA_HOME}/bin/keytool"
    if "$candidate" -help >/dev/null 2>&1; then
      printf "%s" "$candidate"
      return
    fi
  fi

  if command -v keytool >/dev/null 2>&1; then
    candidate="$(command -v keytool)"
    if "$candidate" -help >/dev/null 2>&1; then
      printf "%s" "$candidate"
      return
    fi
  fi

  while IFS= read -r candidate; do
    if [[ -x "$candidate" ]] && "$candidate" -help >/dev/null 2>&1; then
      printf "%s" "$candidate"
      return
    fi
  done < <(
    find \
      /opt/homebrew/Cellar \
      /opt/homebrew/opt \
      /Library/Java/JavaVirtualMachines \
      /Applications \
      -path '*/bin/keytool' \
      -type f \
      2>/dev/null
  )

  echo "Missing usable keytool. Set KEYTOOL or JAVA_HOME to a full JDK install." >&2
  exit 1
}

resolve_keystore_path() {
  local path="${SHAMELL_RELEASE_STORE_FILE:-}"
  if [[ -n "$path" ]]; then
    printf "%s" "$path"
    return
  fi
  local encoded="${SHAMELL_RELEASE_STORE_BASE64:-}"
  if [[ -z "$encoded" ]]; then
    echo "Missing SHAMELL_RELEASE_STORE_FILE or SHAMELL_RELEASE_STORE_BASE64." >&2
    exit 1
  fi
  tmp_keystore="$(mktemp "${TMPDIR:-/tmp}/shamell-release.keystore.XXXXXX")"
  printf "%s" "$encoded" | base64 --decode >"$tmp_keystore"
  printf "%s" "$tmp_keystore"
}

extract_sha256_fingerprint() {
  local keystore_path="$1"
  local output
  output="$(
    "$KEYTOOL_BIN" -list -v \
      -keystore "$keystore_path" \
      -storepass "${SHAMELL_RELEASE_STORE_PASSWORD:-}" \
      -alias "${SHAMELL_RELEASE_KEY_ALIAS:-}" \
      -keypass "${SHAMELL_RELEASE_KEY_PASSWORD:-}" 2>/dev/null
  )" || {
    echo "Could not inspect Android release signing key." >&2
    exit 1
  }
  local fingerprint
  fingerprint="$(
    printf "%s\n" "$output" |
      awk -F': ' '/SHA256:/{print $2; exit}' |
      tr -d '[:space:]'
  )"
  if [[ -z "$fingerprint" ]]; then
    echo "Could not extract SHA256 fingerprint from signing key." >&2
    exit 1
  fi
  printf "%s" "$fingerprint"
}

require_cmd python3
KEYTOOL_BIN="$(resolve_keytool)"

: "${SHAMELL_RELEASE_STORE_PASSWORD:?Missing SHAMELL_RELEASE_STORE_PASSWORD}"
: "${SHAMELL_RELEASE_KEY_ALIAS:?Missing SHAMELL_RELEASE_KEY_ALIAS}"
: "${SHAMELL_RELEASE_KEY_PASSWORD:?Missing SHAMELL_RELEASE_KEY_PASSWORD}"

keystore_path="$(resolve_keystore_path)"
if [[ ! -f "$keystore_path" ]]; then
  echo "Android signing keystore not found: $keystore_path" >&2
  exit 1
fi

android_sha256="$(extract_sha256_fingerprint "$keystore_path")"
ios_app_id="${IOS_TEAM_ID}.${IOS_BUNDLE_ID}"

mkdir -p "$OUTPUT_DIR"

python3 - "$OUTPUT_DIR/apple-app-site-association" "$ios_app_id" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
app_id = sys.argv[2]
path.write_text(
    json.dumps(
        {
            "applinks": {
                "apps": [],
                "details": [
                    {
                        "appID": app_id,
                        "paths": ["/app/*"],
                    }
                ],
            }
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
PY

python3 - "$OUTPUT_DIR/assetlinks.json" "$ANDROID_PACKAGE_NAME" "$android_sha256" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
package_name = sys.argv[2]
fingerprint = sys.argv[3]
path.write_text(
    json.dumps(
        [
            {
                "relation": ["delegate_permission/common.handle_all_urls"],
                "target": {
                    "namespace": "android_app",
                    "package_name": package_name,
                    "sha256_cert_fingerprints": [fingerprint],
                },
            }
        ],
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
PY

echo "Generated:"
echo "  $OUTPUT_DIR/apple-app-site-association"
echo "  $OUTPUT_DIR/assetlinks.json"
echo "Android SHA256 fingerprint: $android_sha256"
