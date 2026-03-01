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

matches="$("${diff_cmd[@]}" | rg -n '^\+[^+].*\b(debugPrint|print|developer\.log)\s*\(' || true)"
if [[ -n "$matches" ]]; then
  echo "[FAIL] New raw debug/log prints found in Flutter lib code" >&2
  echo "$matches" >&2
  echo "       Fix: remove raw prints or route through structured/sanitized telemetry." >&2
  errors=1
else
  echo "[OK]   no new raw debug/log prints in Flutter lib code"
fi

if (( errors != 0 )); then
  exit 1
fi

