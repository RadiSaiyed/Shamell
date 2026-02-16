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

python_files="$(cd "$ROOT" && rg --files -g '*.py' || true)"
if [[ -n "$python_files" ]]; then
  fail "python files still found:\n$python_files"
else
  ok "no python source files found"
fi

if (( errors != 0 )); then
  exit 1
fi

echo "Legacy-artifact guard passed."
