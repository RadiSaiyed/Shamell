#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

errors=0

fail() {
  echo "[FAIL] $1" >&2
  errors=1
}

ok() {
  echo "[OK]   $1"
}

ALLOWLIST_FILE="${ROOT}/scripts/no_secrets_in_urls.allowlist"

SEARCH_ROOTS=(
  services_rs
  crates_rs
  clients/shamell_flutter/lib
  scripts
  .github/scripts
)

RG_FLAGS=(
  -n
  -S
  --no-heading
  --color=never
  --glob '!**/*.min.*'
  --glob '!**/*.lock'
  --glob '!**/Cargo.lock'
  --glob '!**/*.allowlist'
  --glob '!**/target/**'
  --glob '!**/.dart_tool/**'
  --glob '!**/build/**'
  --glob '!**/Pods/**'
)

if ! command -v rg >/dev/null 2>&1; then
  fail "missing required command: rg"
fi

allowlist_paths=()
allowlist_snips=()
if [[ -f "$ALLOWLIST_FILE" ]]; then
  while IFS= read -r raw; do
    line="${raw%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    if [[ "$line" != *"|"* ]]; then
      fail "invalid allowlist entry (missing '|'): $raw"
      continue
    fi
    allowlist_paths+=("${line%%|*}")
    allowlist_snips+=("${line#*|}")
  done < "$ALLOWLIST_FILE"
fi

is_allowlisted() {
  local match_line="$1"
  local file="${match_line%%:*}"
  local i
  for ((i=0; i<${#allowlist_paths[@]}; i++)); do
    local p="${allowlist_paths[$i]}"
    local s="${allowlist_snips[$i]}"
    if [[ "$file" == *"$p"* && "$match_line" == *"$s"* ]]; then
      return 0
    fi
  done
  return 1
}

collect_unallowlisted() {
  local input="$1"
  local out=""
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    if is_allowlisted "$row"; then
      continue
    fi
    out+="${row}"$'\n'
  done <<< "$input"
  printf '%s' "$out"
}

# 1) Disallow "secret-like" query keys in URLs/paths.
# This is intentionally heuristic and aims to prevent accidental leakage via
# logs, caches and referrers. Prefer POST JSON bodies or headers.
#
# Note: we deliberately ignore the custom scheme shamell:// (deep links), since
# those aren't sent over HTTP and would otherwise produce noisy false positives.
secret_keys_re='token|access_token|refresh_token|mailbox_token|internal_secret|secret|session|sid|otp|code|signature|sig|key'
query_key_matches="$(
  rg "${RG_FLAGS[@]}" -i "(?:\\?|&)(${secret_keys_re})=" "${SEARCH_ROOTS[@]}" 2>/dev/null || true
)"
query_key_matches="$(printf '%s\n' "$query_key_matches" | rg -v 'shamell://' || true)"
query_key_matches="$(collect_unallowlisted "$query_key_matches")"

if [[ -n "$query_key_matches" ]]; then
  fail "likely secrets found in URL query strings (move to body/headers; avoid leakage via logs/caches):"
  echo "$query_key_matches" >&2
else
  ok "no secret-like query parameters in URLs (except allowlisted)"
fi

# 2) Disallow query-based QR generation patterns (payload-in-query).
qr_query_matches="$(
  rg "${RG_FLAGS[@]}" -i "qr\\.(png|svg)\\?" "${SEARCH_ROOTS[@]}" 2>/dev/null || true
)"
qr_query_matches="$(collect_unallowlisted "$qr_query_matches")"
if [[ -n "$qr_query_matches" ]]; then
  fail "query-based QR endpoints detected (do not pass payload via URL query):"
  echo "$qr_query_matches" >&2
else
  ok "no query-based QR generation"
fi

if (( errors != 0 )); then
  echo "Hint: if a third-party protocol mandates query-string auth, add a *narrow* allowlist entry in scripts/no_secrets_in_urls.allowlist." >&2
  exit 1
fi

echo "No-secrets-in-URLs guard passed."
