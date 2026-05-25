#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "single app convergence guard failed: $*" >&2
  exit 1
}

require_file() {
  local file="$1"
  [[ -f "$file" ]] || fail "missing file: $file"
}

require_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || fail "missing directory: $dir"
}

require_absent() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "parallel app artifact still present: $path"
}

require_fixed() {
  local file="$1"
  local text="$2"
  local label="$3"
  grep -Fq -- "$text" "$file" || fail "missing marker ($label) in $file"
}

required_files=(
  "docs/v2/README.md"
  "docs/v2/REWRITE_36_CHECKLIST.md"
  "docs/v2/product/core-scope.md"
  "docs/v2/product/engagement-principles.md"
  "docs/v2/architecture/target.md"
  "docs/v2/backend/modular-monolith.md"
  "docs/v2/frontend/flutter-feature-first.md"
  "docs/v2/frontend/design-system.md"
  "docs/v2/frontend/interaction-principles.md"
  "docs/v2/contracts/openapi.yaml"
  "docs/v2/metrics/events.yaml"
  "docs/v2/metrics/kpi-framework.md"
  "docs/v2/migration/strangler-plan.md"
  "docs/engineering/definition_of_done.md"
  "docs/engineering/conventions_v2.md"
  ".github/pull_request_template.md"
  "docs/adr/ADR_TEMPLATE.md"
  "docs/adr/0002-v2-rewrite-foundation.md"
  "clients/shamell_flutter/lib/main.dart"
  "clients/shamell_flutter/lib/src/main_home.dart"
  "clients/shamell_flutter/lib/src/main_shell.dart"
  "clients/shamell_flutter/lib/core/chat/shamell_chat_page.dart"
  "clients/shamell_flutter/lib/core/payments/payments_shell.dart"
  "clients/shamell_flutter/lib/core/shamell_moments_page.dart"
  "clients/shamell_flutter/lib/core/v2_auth_strangler.dart"
  "clients/shamell_flutter/lib/core/v2_chat_strangler.dart"
  "clients/shamell_flutter/test/v2_auth_strangler_test.dart"
  "clients/shamell_flutter/test/v2_chat_strangler_test.dart"
  "clients/shamell_flutter/test/outbound_ratchet_bootstrap_test.dart"
  "clients/shamell_flutter/test/settings_hub_test.dart"
)

for file in "${required_files[@]}"; do
  require_file "$file"
done

require_absent "clients/shamell_flutter/lib/main_v2.dart"
require_absent "clients/shamell_flutter/lib/v2"
require_absent "clients/shamell_flutter/test/v2"

if rg -n \
  "package:shamell_flutter/v2|V2MainApp|V2ShellPage|V2Bootstrap|clients/shamell_flutter/lib/v2|v2/features|v2/design" \
  clients/shamell_flutter/lib \
  clients/shamell_flutter/test \
  docs/wechat_messaging_parity.md \
  docs/v2/frontend \
  -g '*.dart' -g '*.md'; then
  fail "stale V2 Flutter app reference found"
fi

checklist="docs/v2/REWRITE_36_CHECKLIST.md"
item_count="$(grep -Ec '^- \[[ x]\] [0-9]+\.' "$checklist")"
[[ "$item_count" -eq 36 ]] || fail "expected 36 checklist items, got $item_count"
checked_count="$(grep -Ec '^- \[x\] [0-9]+\.' "$checklist")"
[[ "$checked_count" -eq 36 ]] || fail "expected 36 checked items, got $checked_count"

scope_doc="docs/v2/product/core-scope.md"
require_fixed "$scope_doc" "Auth and session lifecycle." "core flow auth"
require_fixed "$scope_doc" "Chat (1:1, groups, core messaging)." "core flow chat"
require_fixed "$scope_doc" "Payments (wallet, transfer, history)." "core flow payments"
require_fixed "$scope_doc" "## Explicitly out of scope for initial V2" "explicit out of scope"
require_fixed "$scope_doc" "## Product rules" "in/out product rules"
require_fixed "$scope_doc" "## Scope-first planning workflow" "scope-first planning"
require_fixed "$scope_doc" "## Core-flow-first sequencing" "core-flow sequencing"
require_fixed "$scope_doc" "Non-core work must be behind a feature flag" "non-core feature flag rule"

frontend_doc="docs/v2/frontend/flutter-feature-first.md"
require_fixed "$frontend_doc" "Use one active Flutter app." "single app rule"
require_fixed "$frontend_doc" "Do not add a second Flutter entrypoint" "no second entrypoint"
require_fixed "$frontend_doc" "clients/shamell_flutter/lib/core" "active core location"
require_fixed "$frontend_doc" "clients/shamell_flutter/lib/src" "active shell location"
require_fixed "$frontend_doc" "Widgets stay presentational where possible." "presentational widget rule"
require_fixed "$frontend_doc" "one state-management style per feature module" "single state-management style"
require_fixed "$frontend_doc" "empty/loading/error handling" "standard UI states"
require_fixed "$frontend_doc" "Fast first success in <= 30s" "first success objective"

design_doc="docs/v2/frontend/design-system.md"
require_fixed "$design_doc" "Single-App Design System Baseline" "design system title"
require_fixed "$design_doc" "clients/shamell_flutter/lib/core/design_tokens.dart" "active design tokens"
require_fixed "$design_doc" "No separate V2 component kit is allowed" "no parallel component kit"

arch_doc="docs/v2/architecture/target.md"
require_fixed "$arch_doc" "modular boundaries" "modular-monolith target"
require_fixed "$arch_doc" "- \`auth\`" "auth boundary"
require_fixed "$arch_doc" "- \`chat\`" "chat boundary"
require_fixed "$arch_doc" "- \`payments\`" "payments boundary"

backend_doc="docs/v2/backend/modular-monolith.md"
require_fixed "$backend_doc" "domain/" "backend domain layer"
require_fixed "$backend_doc" "application/" "backend application layer"
require_fixed "$backend_doc" "infrastructure/" "backend infrastructure layer"
require_fixed "$backend_doc" "api/" "backend api layer"
require_fixed "$backend_doc" "No framework-specific types in \`domain\`." "domain framework leakage rule"
require_fixed "$backend_doc" "## Contract-first" "contract-first process"
require_fixed "$backend_doc" "Async/event delivery only when required" "limited async/events"

events_doc="docs/v2/metrics/events.yaml"
require_fixed "$events_doc" "events:" "telemetry event catalog"
require_fixed "$events_doc" "v2_activation_started" "activation start event"
require_fixed "$events_doc" "v2_activation_completed" "activation complete event"

for domain in auth chat payments; do
  require_dir "services_rs/v2_core/$domain"
  for layer in domain application infrastructure api; do
    layer_dir="services_rs/v2_core/$domain/$layer"
    require_dir "$layer_dir"
    layer_files="$(find "$layer_dir" -maxdepth 1 -type f | wc -l | tr -d ' ')"
    [[ "$layer_files" -ge 1 ]] || fail "layer has no files: $layer_dir"
  done
done
require_dir "services_rs/v2_core/shared"

echo "single app convergence guard passed"
