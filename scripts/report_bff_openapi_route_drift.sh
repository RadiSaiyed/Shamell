#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_RS="$ROOT/services_rs/bff_gateway/src/main.rs"
OPENAPI="$ROOT/docs/v2/contracts/openapi.yaml"
EXPORTER="$ROOT/scripts/export_bff_runtime_openapi_surface.py"
STRICT=0

if [[ "${1:-}" == "--strict" ]]; then
  STRICT=1
  shift
fi

if [[ $# -ne 0 ]]; then
  echo "usage: $(basename "$0") [--strict]" >&2
  exit 2
fi

fail() {
  echo "BFF/OpenAPI drift report failed: $*" >&2
  exit 1
}

[[ -f "$MAIN_RS" ]] || fail "missing file: $MAIN_RS"
[[ -f "$OPENAPI" ]] || fail "missing file: $OPENAPI"
[[ -f "$EXPORTER" ]] || fail "missing file: $EXPORTER"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

runtime_routes="$tmpdir/runtime_routes.txt"
spec_routes="$tmpdir/spec_routes.txt"
runtime_pairs="$tmpdir/runtime_pairs.txt"
spec_pairs="$tmpdir/spec_pairs.txt"
undocumented_runtime_routes="$tmpdir/undocumented_runtime_routes.txt"
missing_runtime_routes="$tmpdir/missing_runtime_routes.txt"
undocumented_runtime_pairs="$tmpdir/undocumented_runtime_pairs.txt"
missing_runtime_pairs="$tmpdir/missing_runtime_pairs.txt"

python3 "$EXPORTER" --main-rs "$MAIN_RS" --format route-pairs | sort -u >"$runtime_pairs"
cut -d' ' -f2- "$runtime_pairs" | sort -u >"$runtime_routes"

awk '
  /^  \/.*:$/ {
    path=$1
    sub(/:$/, "", path)
    next
  }
  /^    (get|post|put|patch|delete):$/ {
    method=$1
    sub(/:$/, "", method)
    if (path != "") {
      print toupper(method) " " path
    }
  }
' "$OPENAPI" | sed -E 's/\{([^}]+)\}/:\1/g' | sort -u >"$spec_pairs"
cut -d' ' -f2- "$spec_pairs" | sort -u >"$spec_routes"

comm -23 "$runtime_routes" "$spec_routes" >"$undocumented_runtime_routes"
comm -13 "$runtime_routes" "$spec_routes" >"$missing_runtime_routes"
comm -23 "$runtime_pairs" "$spec_pairs" >"$undocumented_runtime_pairs"
comm -13 "$runtime_pairs" "$spec_pairs" >"$missing_runtime_pairs"

echo "BFF/OpenAPI route drift report"
echo "  runtime routes: $(wc -l <"$runtime_routes" | tr -d ' ')"
echo "  spec routes:    $(wc -l <"$spec_routes" | tr -d ' ')"
echo "  runtime operations: $(wc -l <"$runtime_pairs" | tr -d ' ')"
echo "  spec operations:    $(wc -l <"$spec_pairs" | tr -d ' ')"
echo "  undocumented runtime routes: $(wc -l <"$undocumented_runtime_routes" | tr -d ' ')"
echo "  spec-only routes:            $(wc -l <"$missing_runtime_routes" | tr -d ' ')"
echo "  undocumented runtime operations: $(wc -l <"$undocumented_runtime_pairs" | tr -d ' ')"
echo "  spec-only operations:            $(wc -l <"$missing_runtime_pairs" | tr -d ' ')"
echo

if [[ -s "$undocumented_runtime_routes" ]]; then
  echo "Undocumented runtime routes:"
  sed 's/^/  - /' "$undocumented_runtime_routes"
  echo
fi

if [[ -s "$missing_runtime_routes" ]]; then
  echo "Spec routes missing from runtime:"
  sed 's/^/  - /' "$missing_runtime_routes"
  echo
fi

if [[ -s "$undocumented_runtime_pairs" ]]; then
  echo "Undocumented runtime operations:"
  sed 's/^/  - /' "$undocumented_runtime_pairs"
  echo
fi

if [[ -s "$missing_runtime_pairs" ]]; then
  echo "Spec operations missing from runtime:"
  sed 's/^/  - /' "$missing_runtime_pairs"
fi

if [[ $STRICT -eq 1 ]] && {
  [[ -s "$undocumented_runtime_routes" ]] ||
  [[ -s "$missing_runtime_routes" ]] ||
  [[ -s "$undocumented_runtime_pairs" ]] ||
  [[ -s "$missing_runtime_pairs" ]];
}; then
  exit 1
fi
