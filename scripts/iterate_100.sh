#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ITERATIONS="${1:-100}"
REPORT_DIR="${APP_DIR}/ops/reports"
mkdir -p "${REPORT_DIR}"
REPORT_FILE="${REPORT_DIR}/iterate-100-$(date +%Y%m%d-%H%M%S).log"

if ! [[ "${ITERATIONS}" =~ ^[0-9]+$ ]] || [[ "${ITERATIONS}" -lt 1 ]]; then
  echo "ITERATIONS must be a positive integer." >&2
  exit 1
fi

run_guards() {
  "${APP_DIR}/scripts/check_no_legacy_artifacts.sh"
  "${APP_DIR}/scripts/check_internal_port_exposure.sh"
  "${APP_DIR}/scripts/check_nginx_edge_hardening.sh"
  "${APP_DIR}/scripts/check_deploy_env_invariants.sh"
  "${APP_DIR}/scripts/check_frontend_error_sanitization.sh"
  "${APP_DIR}/scripts/check_no_secrets_in_urls.sh"
}

echo "Starting ${ITERATIONS} Rust quality/security iterations" | tee -a "${REPORT_FILE}"
echo "Report file: ${REPORT_FILE}" | tee -a "${REPORT_FILE}"

for i in $(seq 1 "${ITERATIONS}"); do
  printf '[%03d/%03d] checks...\n' "${i}" "${ITERATIONS}" | tee -a "${REPORT_FILE}"
  (
    cd "${APP_DIR}"
    cargo fmt --check
    cargo clippy --all-targets --all-features -- -D warnings
    run_guards
  )

  if (( i % 10 == 0 || i == ITERATIONS )); then
    (
      cd "${APP_DIR}"
      cargo test
    )
    printf '[%03d/%03d] tests ok\n' "${i}" "${ITERATIONS}" | tee -a "${REPORT_FILE}"
  fi
done

echo "All ${ITERATIONS} iterations completed successfully." | tee -a "${REPORT_FILE}"
