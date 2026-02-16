#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0
has_rg=0
if command -v rg >/dev/null 2>&1; then
  has_rg=1
fi

fail() {
  echo "[FAIL] $1" >&2
  errors=1
}

ok() {
  echo "[OK]   $1"
}

contains_pattern() {
  local root="$1"
  local pattern="$2"
  local fixed="${3:-0}"
  if (( has_rg == 1 )); then
    if (( fixed == 1 )); then
      rg -n -S --glob '!**/*.min.*' -F -- "$pattern" "$root" >/dev/null
    else
      rg -n --glob '!**/*.min.*' -- "$pattern" "$root" >/dev/null
    fi
  else
    if (( fixed == 1 )); then
      grep -R -I -n -F --exclude='*.min.*' -- "$pattern" "$root" >/dev/null
    else
      grep -R -I -n -E --exclude='*.min.*' -- "$pattern" "$root" >/dev/null
    fi
  fi
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
    if [[ -d "$ROOT/$root" ]] && contains_pattern "$ROOT/$root" "$prefix" 0; then
      fail "found banned route prefix '$prefix' under $root"
    fi
  done
done

for term in "${BANNED_STRINGS[@]}"; do
  for root in "${SEARCH_ROOTS[@]}"; do
    if [[ -d "$ROOT/$root" ]] && contains_pattern "$ROOT/$root" "$term" 1; then
      fail "found banned string '$term' under $root"
    fi
  done
done

python_files="$(cd "$ROOT" && git ls-files '*.py' || true)"
if [[ -n "$python_files" ]]; then
  fail "python files still found:\n$python_files"
else
  ok "no python source files found"
fi

if (( errors != 0 )); then
  exit 1
fi

echo "Legacy-artifact guard passed."
