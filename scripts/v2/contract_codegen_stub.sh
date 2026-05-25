#!/usr/bin/env bash
set -euo pipefail

spec="docs/v2/contracts/openapi.yaml"

if [[ ! -f "$spec" ]]; then
  echo "OpenAPI spec not found: $spec" >&2
  exit 1
fi

echo "Contract-first stub"
echo "- Validate OpenAPI: $spec"
echo "- Current file is the generated live route/method surface; enrich schemas before relying on codegen for full clients"
echo "- Generate server/client stubs with your selected generator"
echo "- Commit generated code separately from handwritten logic"
