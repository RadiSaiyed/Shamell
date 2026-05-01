#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "v2 foundation check failed: $*" >&2
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

require_fixed() {
  local file="$1"
  local text="$2"
  local label="$3"
  grep -Fq -- "$text" "$file" || fail "missing marker ($label) in $file"
}

require_regex() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  grep -Eq -- "$pattern" "$file" || fail "missing pattern ($label) in $file"
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
  "clients/shamell_flutter/lib/main_v2.dart"
  "clients/shamell_flutter/lib/v2/app/v2_main_app.dart"
  "clients/shamell_flutter/lib/v2/design/tokens.dart"
  "clients/shamell_flutter/lib/v2/design/motion.dart"
  "clients/shamell_flutter/lib/v2/design/components/v2_primary_button.dart"
  "clients/shamell_flutter/lib/v2/design/components/v2_status_panel.dart"
  "clients/shamell_flutter/lib/v2/design/components/v2_surface_card.dart"
  "clients/shamell_flutter/lib/v2/core/flags/feature_flag.dart"
  "clients/shamell_flutter/lib/v2/core/analytics/v2_event_catalog.dart"
  "services_rs/v2_core/README.md"
  "services_rs/v2_core/module_layout.md"
)

for file in "${required_files[@]}"; do
  require_file "$file"
done

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

frontend_doc="docs/v2/frontend/flutter-feature-first.md"
require_fixed "$frontend_doc" "feature-first organization" "feature-first structure"
require_fixed "$frontend_doc" "v2/features/<feature>/domain" "frontend domain layer"
require_fixed "$frontend_doc" "v2/features/<feature>/application" "frontend application layer"
require_fixed "$frontend_doc" "v2/features/<feature>/infrastructure" "frontend infrastructure layer"
require_fixed "$frontend_doc" "v2/features/<feature>/presentation" "frontend presentation layer"
require_fixed "$frontend_doc" "Shared design tokens/components under \`v2/design\`." "design-system location"
require_fixed "$frontend_doc" "Widgets stay presentational where possible." "presentational widget rule"
require_fixed "$frontend_doc" "one state-management style per feature module" "single state-management style"
require_fixed "$frontend_doc" "empty/loading/error handling" "standard UI states"
require_fixed "$frontend_doc" "Fast first success in <= 30s" "first success objective"

design_doc="docs/v2/frontend/design-system.md"
require_fixed "$design_doc" "## Tokens" "design token baseline"
require_fixed "$design_doc" "## Components" "component kit baseline"
require_fixed "$design_doc" "## Motion" "motion guidelines"

engagement_doc="docs/v2/product/engagement-principles.md"
require_fixed "$engagement_doc" "## Goal" "engagement goal"
require_fixed "$engagement_doc" "## Allowed patterns" "engagement allowed patterns"
require_fixed "$engagement_doc" "Personalized quick actions on home." "personalized home loop"
require_fixed "$engagement_doc" "## Disallowed patterns (no dark patterns)" "no dark pattern policy"

dod_doc="docs/engineering/definition_of_done.md"
require_fixed "$dod_doc" "Definition Of Done" "definition of done"
require_fixed "$dod_doc" "Security and privacy checks are complete." "security/privacy checks"
require_fixed "$dod_doc" "Performance impact is measured (p95 latency/render)." "performance checks"

pr_template=".github/pull_request_template.md"
require_fixed "$pr_template" "## Quality Gate" "pr quality gates"
require_fixed "$pr_template" "## Rollout Plan" "rollout planning in pr template"

conventions_doc="docs/engineering/conventions_v2.md"
require_fixed "$conventions_doc" "## Backend" "backend conventions"
require_fixed "$conventions_doc" "## Flutter" "frontend conventions"
require_fixed "$conventions_doc" "## Contracts" "contract conventions"
require_fixed "$conventions_doc" "## Testing (pyramid expectation)" "test pyramid expectation"

events_doc="docs/v2/metrics/events.yaml"
require_fixed "$events_doc" "events:" "telemetry event catalog"
require_fixed "$events_doc" "v2_activation_started" "activation start event"
require_fixed "$events_doc" "v2_activation_completed" "activation complete event"

event_catalog_file="clients/shamell_flutter/lib/v2/core/analytics/v2_event_catalog.dart"
require_fixed "$event_catalog_file" "static const String activationStarted" "typed event activationStarted"
require_fixed "$event_catalog_file" "static const String activationCompleted" "typed event activationCompleted"
require_fixed "$event_catalog_file" "static const String authSignInSucceeded" "typed event authSignInSucceeded"

kpi_doc="docs/v2/metrics/kpi-framework.md"
require_fixed "$kpi_doc" "## Product KPIs" "kpi framework product"
require_fixed "$kpi_doc" "## Reliability KPIs" "kpi framework reliability"
require_fixed "$kpi_doc" "## UX KPIs" "kpi framework ux"

migration_doc="docs/v2/migration/strangler-plan.md"
require_fixed "$migration_doc" "## Phases" "strangler phases"
require_fixed "$migration_doc" "Phase 1: migrate auth flow." "auth migration phase"
require_fixed "$migration_doc" "Phase 2: migrate chat flow." "chat migration phase"
require_fixed "$migration_doc" "Phase 3: migrate payments flow." "payments migration phase"
require_fixed "$migration_doc" "## Rollout and rollback gate policy" "rollout/rollback policy"
require_fixed "$migration_doc" "### Feature-flag-first cutover rule" "feature-flag-first rule"

index_doc="docs/v2/README.md"
require_fixed "$index_doc" "Program tracker: \`docs/v2/REWRITE_36_CHECKLIST.md\`" "program index"

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

for feature in auth chat payments; do
  feature_root="clients/shamell_flutter/lib/v2/features/$feature"
  require_dir "$feature_root/domain"
  require_dir "$feature_root/application"
  require_dir "$feature_root/infrastructure"
  require_dir "$feature_root/presentation"
  dart_files="$(find "$feature_root" -type f -name '*.dart' | wc -l | tr -d ' ')"
  [[ "$dart_files" -ge 4 ]] || fail "insufficient feature files for $feature (expected >=4, got $dart_files)"
done

flags_file="clients/shamell_flutter/lib/v2/core/flags/feature_flag.dart"
require_fixed "$flags_file" "authV2" "auth feature flag"
require_fixed "$flags_file" "chatV2" "chat feature flag"
require_fixed "$flags_file" "paymentsV2" "payments feature flag"

echo "v2 foundation artifacts and 36-point guardrails present"
