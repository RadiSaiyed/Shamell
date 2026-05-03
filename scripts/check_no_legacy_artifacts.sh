#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

fail() {
  echo "[FAIL] $1" >&2
  errors=1
}

ok() {
  echo "[OK]   $1"
}

BANNED_PATHS=(
  "NonShamell"
  "apps"
  "libs/shamell_shared/python"
  "tests"
  "requirements.txt"
)

for rel in "${BANNED_PATHS[@]}"; do
  if [[ -e "$ROOT/$rel" ]]; then
    fail "legacy path still present: $rel"
  else
    ok "legacy path absent: $rel"
  fi
done

BANNED_ROUTE_PREFIXES=(
  "/courier"
  "/stays"
  "/carrental"
  "/commerce"
  "/agriculture"
  "/livestock"
  "/building"
  "/pms"
  "/payments-debug"
  "/chat/resolve"
)

# Product hardening: explicitly ban removed features so they can't creep back in.
BANNED_STRINGS=(
  # Branding: prevent accidental regressions to legacy names.
  "Mirsaal"
  "WeChat"
  "wechat"
  "Threema"

  "redpacket"
  "Red packet"
  "/hb"
  "hongbao"
  "shamell://friend"
  "host: 'friend'"
  "host: \"friend\""
  "people_nearby"
  "peopleNearby"
  "sticker"
)

SEARCH_ROOTS=(
  "services_rs"
  "crates_rs"
  "clients/shamell_flutter/lib"
)

for prefix in "${BANNED_ROUTE_PREFIXES[@]}"; do
  for root in "${SEARCH_ROOTS[@]}"; do
    if [[ -d "$ROOT/$root" ]] && rg -n --glob '!**/*.min.*' -- "$prefix" "$ROOT/$root" >/dev/null; then
      fail "found banned route prefix '$prefix' under $root"
    fi
  done
done

for term in "${BANNED_STRINGS[@]}"; do
  for root in "${SEARCH_ROOTS[@]}"; do
    if [[ -d "$ROOT/$root" ]] && rg -n -S --glob '!**/*.min.*' -- "$term" "$ROOT/$root" >/dev/null; then
      fail "found banned string '$term' under $root"
    fi
  done
done

ALLOWED_PYTHON_FILES=(
  "scripts/export_bff_runtime_openapi_surface.py"
  "scripts/replace_jira_placeholders.py"
)

is_allowed_python_file() {
  local rel="$1"
  local allowed
  for allowed in "${ALLOWED_PYTHON_FILES[@]}"; do
    if [[ "$rel" == "$allowed" ]]; then
      return 0
    fi
  done
  return 1
}

python_files="$(
  cd "$ROOT"
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    if ! is_allowed_python_file "$rel"; then
      printf '%s\n' "$rel"
    fi
  done < <(rg --files -g '*.py' || true)
)"
if [[ -n "$python_files" ]]; then
  fail "unexpected python files found:\n$python_files"
else
  ok "no unexpected python source files found"
fi

if (( errors != 0 )); then
  exit 1
fi

echo "Legacy-artifact guard passed."
