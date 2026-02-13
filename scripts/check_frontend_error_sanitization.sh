#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

errors=0

target_paths=(
  clients/shamell_flutter/lib
)

range=""
if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" && -n "${GITHUB_BASE_REF:-}" ]]; then
  base_ref="${GITHUB_BASE_REF}"
  # Best-effort fetch in case the base branch is not locally present.
  git fetch --no-tags --depth=1 origin "+refs/heads/${base_ref}:refs/remotes/origin/${base_ref}" >/dev/null 2>&1 || true
  if git rev-parse --verify "origin/${base_ref}" >/dev/null 2>&1; then
    range="origin/${base_ref}...HEAD"
  fi
fi

if [[ -z "$range" ]] && git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
  range="HEAD~1...HEAD"
fi

diff_cmd=(git diff --unified=0)
if [[ -n "$range" ]]; then
  diff_cmd+=("$range")
fi
diff_cmd+=(-- "${target_paths[@]}")

check_added_pattern() {
  local label="$1"
  local pattern="$2"
  local guidance="$3"
  local matches
  matches="$("${diff_cmd[@]}" | rg -n "$pattern" || true)"
  if [[ -n "$matches" ]]; then
    echo "[FAIL] $label" >&2
    echo "$matches" >&2
    echo "       Fix: $guidance" >&2
    errors=1
  else
    echo "[OK]   $label"
  fi
}

check_added_pattern \
  "No new UI exception leaks via e.toString()" \
  '^\+[^+].*e\.toString\(\)' \
  "map exceptions to safe user messages (e.g. sanitizeHttpError/sanitizeExceptionForUi)."

check_added_pattern \
  "No new raw backend-body rendering in UI" \
  '^\+[^+].*(resp\.body\.isNotEmpty[[:space:]]*\?[[:space:]]*resp\.body|HTTP[[:space:]]*\$\{resp\.statusCode\}:[[:space:]]*\$\{resp\.body\}|_error[[:space:]]*=[[:space:]]*resp\.body|error[[:space:]]*=[[:space:]]*resp\.body)' \
  "never surface resp.body directly; convert to a generic/sanitized message."

if (( errors != 0 )); then
  exit 1
fi

echo "Frontend error sanitization guard passed."
