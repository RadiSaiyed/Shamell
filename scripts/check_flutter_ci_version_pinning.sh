#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "[FAIL] missing required command: rg" >&2
  exit 1
fi

if [[ ! -d .github/workflows ]]; then
  echo "[OK]   no .github/workflows directory found"
  exit 0
fi

flutter_uses_count="$(
  rg -n --glob '*.yml' --glob '*.yaml' 'uses:\s*subosito/flutter-action@' .github/workflows \
    | wc -l | tr -d ' '
)"

if [[ "$flutter_uses_count" -eq 0 ]]; then
  echo "[OK]   no subosito/flutter-action usage in workflows"
  exit 0
fi

errors=0

# Ban moving-target channel pinning.
stable_hits="$(
  rg -n --glob '*.yml' --glob '*.yaml' '^\s*channel:\s*stable\s*$' .github/workflows || true
)"
if [[ -n "$stable_hits" ]]; then
  echo "[FAIL] Flutter workflows must not use moving target 'channel: stable'" >&2
  echo "$stable_hits" >&2
  errors=1
fi

# Require explicit flutter-version pin when flutter-action is used.
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if ! rg -q 'flutter-version:\s*"?[0-9]+\.[0-9]+\.[0-9]+' "$path"; then
    echo "[FAIL] missing flutter-version pin in $path" >&2
    errors=1
  fi
done < <(rg -l --glob '*.yml' --glob '*.yaml' 'uses:\s*subosito/flutter-action@' .github/workflows || true)

if (( errors != 0 )); then
  echo "[FAIL] Flutter workflow version pinning guard failed" >&2
  exit 1
fi

echo "[OK]   Flutter workflows pin flutter-version and avoid channel: stable"
