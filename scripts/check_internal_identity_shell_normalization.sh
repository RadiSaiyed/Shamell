#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/lib_internal_identity.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

payload_file="${tmp_dir}/payload.json"
printf '{}' > "$payload_file"

headers="$(
  internal_identity_build_curl_headers \
    "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=" \
    " Security-Reporter " \
    " BFF " \
    "POST" \
    "http://127.0.0.1:8080/internal/security/alerts" \
    "$payload_file"
)"

require_output() {
  local needle="$1"
  local label="$2"
  if grep -Fq "$needle" <<<"$headers"; then
    echo "[OK]   $label"
  else
    echo "[FAIL] $label" >&2
    printf '%s\n' "$headers" >&2
    exit 1
  fi
}

require_output 'X-Internal-Service-Id: security-reporter' 'service id is trimmed and lowercased before signing'
require_output 'X-Internal-Audience: bff' 'audience is trimmed and lowercased before signing'

echo "Internal identity shell normalization check passed."
