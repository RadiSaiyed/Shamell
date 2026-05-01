#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/docs/v2/contracts/openapi.yaml"
EXPORTER="$ROOT/scripts/export_bff_runtime_openapi_surface.py"

fail() {
  echo "BFF runtime OpenAPI surface freshness check failed: $*" >&2
  exit 1
}

[[ -f "$SPEC" ]] || fail "missing file: $SPEC"
[[ -f "$EXPORTER" ]] || fail "missing file: $EXPORTER"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

python3 "$EXPORTER" >"$tmp"

if ! diff -u "$SPEC" "$tmp"; then
  fail "docs/v2/contracts/openapi.yaml is stale; regenerate it from the exporter"
fi
