ITERATIONS ?= 100

.PHONY: help fmt clippy test audit deny guards check iterate

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
	cargo audit -D warnings

deny:
	@command -v cargo-deny >/dev/null 2>&1 || { \
		echo "cargo-deny is not installed. Install with:"; \
		echo "  cargo install cargo-deny --locked --version 0.19.0"; \
		exit 1; \
	}
	cargo deny check licenses bans sources

guards:
	./scripts/check_no_legacy_artifacts.sh
	./scripts/check_internal_port_exposure.sh
	./scripts/check_nginx_edge_hardening.sh
	./scripts/check_cors_hardening.sh
	./scripts/check_deploy_env_invariants.sh
	./scripts/check_frontend_error_sanitization.sh
	./scripts/check_no_secrets_in_urls.sh

check: fmt clippy test audit deny guards

iterate:
	bash scripts/iterate_100.sh "$(ITERATIONS)"
