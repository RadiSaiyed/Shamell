ITERATIONS ?= 100
E2E_WITH_FRONTEND ?= 1
E2E_BASE_PORT ?= 19480
E2E_ARTIFACT_DIR ?= .artifacts/e2e

OPS_ENV ?= dev

.PHONY: help fmt clippy test audit deny guards check iterate e2e-internal ride-release-gate regulatory-snapshot

help:
	@echo "Targets:"
	@echo "  fmt       Run cargo fmt --check"
	@echo "  clippy    Run cargo clippy with warnings as errors"
	@echo "  test      Run cargo test"
	@echo "  audit     Run cargo audit (RustSec)"
	@echo "  deny      Run cargo deny (licenses/bans/sources)"
	@echo "  guards    Run repository hardening guard scripts"
	@echo "  check     Run fmt + clippy + test + audit + deny + guards"
	@echo "  iterate   Run scripts/iterate_100.sh (ITERATIONS=$(ITERATIONS))"
	@echo "  e2e-internal  Run scripts/e2e_internal.sh and export logs to $(E2E_ARTIFACT_DIR)"
	@echo "  ride-release-gate  Run ./scripts/ops.sh $(OPS_ENV) ride-release-gate"
	@echo "  regulatory-snapshot  Run ./scripts/regulatory_reporting_snapshot.sh"

fmt:
	cargo fmt --check

clippy:
	cargo clippy --all-targets --all-features -- -D warnings

test:
	cargo test

audit:
	@command -v cargo-audit >/dev/null 2>&1 || { \
		echo "cargo-audit is not installed. Install with:"; \
		echo "  cargo install cargo-audit --locked --version 0.22.1"; \
		exit 1; \
	}
	./scripts/cargo_audit_retry.sh

deny:
	@command -v cargo-deny >/dev/null 2>&1 || { \
		echo "cargo-deny is not installed. Install with:"; \
		echo "  cargo install cargo-deny --locked --version 0.19.0"; \
		exit 1; \
	}
	cargo deny check licenses bans sources

guards:
	# check_no_legacy_artifacts.sh is paused on this branch — it bans
	# V1 super-app strings that the active V1 client legitimately uses
	# (see .github/workflows/ci.yml comment for details).
	# ./scripts/check_no_legacy_artifacts.sh
	./scripts/check_internal_port_exposure.sh
	./scripts/check_nginx_edge_hardening.sh
	./scripts/check_cloudflare_realip_freshness.sh
	./scripts/check_update_cloudflare_ip_ranges_validation.sh
	./scripts/check_cloudflare_sync_freshness_guard.sh
	./scripts/check_ops_edge_commands.sh
	./scripts/check_ops_edge_preflight.sh
	./scripts/check_ops_report_exit_semantics.sh
	./scripts/check_ride_report_timer_systemd_unit.sh
	./scripts/check_sync_hetzner_ride_report_timer.sh
	./scripts/check_cors_hardening.sh
	./scripts/check_deploy_env_invariants.sh
	./scripts/check_trusted_proxy_smoke_headers.sh
	./scripts/check_ci_trusted_proxy_smoke.sh
	./scripts/check_dashboard_proxy_trusted_proxy_guard.sh
	./scripts/check_frontend_error_sanitization.sh
	./scripts/check_no_secrets_in_urls.sh

check: fmt clippy test audit deny guards

iterate:
	bash scripts/iterate_100.sh "$(ITERATIONS)"

e2e-internal:
	@set -eu; \
	mkdir -p "$(E2E_ARTIFACT_DIR)"; \
	stamp="$$(date +%Y%m%d-%H%M%S)"; \
	run_dir="$(E2E_ARTIFACT_DIR)/e2e-$$stamp"; \
	mkdir -p "$$run_dir"; \
	run_log="$$run_dir/e2e.stdout.log"; \
	args="--base-port $(E2E_BASE_PORT)"; \
	if [ "$(E2E_WITH_FRONTEND)" = "1" ]; then \
	  args="$$args --with-frontend"; \
	fi; \
	echo "[make] running ./scripts/e2e_internal.sh $$args"; \
	if ./scripts/e2e_internal.sh $$args >"$$run_log" 2>&1; then \
	  cat "$$run_log"; \
	else \
	  cat "$$run_log"; \
	  echo "[make][error] internal e2e failed; artifacts kept at $$run_dir" >&2; \
	  exit 1; \
	fi; \
	src_log_dir="$$(awk -F': ' '/^Logs: /{print $$2}' "$$run_log" | tail -n1)"; \
	if [ -n "$$src_log_dir" ] && [ -d "$$src_log_dir" ]; then \
	  mkdir -p "$$run_dir/service-logs"; \
	  cp -R "$$src_log_dir"/. "$$run_dir/service-logs"/; \
	  echo "$$src_log_dir" > "$$run_dir/source_log_dir.txt"; \
	else \
	  echo "[make][warn] could not resolve service log dir from e2e output" >&2; \
	fi; \
	  echo "[make] e2e artifacts: $$run_dir"

ride-release-gate:
	./scripts/ops.sh "$(OPS_ENV)" ride-release-gate

regulatory-snapshot:
	./scripts/regulatory_reporting_snapshot.sh
