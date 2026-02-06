#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ITERATIONS="${1:-100}"
PYTHON_BIN="${PYTHON_BIN:-${APP_DIR}/.venv311/bin/python}"
REPORT_DIR="${APP_DIR}/ops/reports"
mkdir -p "${REPORT_DIR}"
REPORT_FILE="${REPORT_DIR}/iterate-100-$(date +%Y%m%d-%H%M%S).log"

if ! [[ "${ITERATIONS}" =~ ^[0-9]+$ ]] || [[ "${ITERATIONS}" -lt 1 ]]; then
  echo "ITERATIONS must be a positive integer." >&2
  exit 1
fi

if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "Python venv not found at ${PYTHON_BIN}. Run: make venv" >&2
  exit 1
fi

check_security_guards() {
  local matches
  matches="$(
    rg -n \
      -e '(^|[^[:alnum:]_])eval\(' \
      -e '(^|[^[:alnum:]_])exec\(' \
      -e 'subprocess\.[A-Za-z_]+\([^)]*shell\s*=\s*True' \
      -e 'verify\s*=\s*False' \
      -e 'allow_origins\s*=\s*\[[^]]*["'"'"']\*["'"'"']' \
      src scripts ops tests -S || true
  )"
  if [[ -n "${matches}" ]]; then
    echo "[security-guard] potential risky patterns found:" | tee -a "${REPORT_FILE}" >&2
    echo "${matches}" | tee -a "${REPORT_FILE}" >&2
    return 1
  fi
}

echo "Starting ${ITERATIONS} quality/security iterations" | tee -a "${REPORT_FILE}"
echo "Report file: ${REPORT_FILE}" | tee -a "${REPORT_FILE}"

for i in $(seq 1 "${ITERATIONS}"); do
  printf '[%03d/%03d] checks...\n' "${i}" "${ITERATIONS}" | tee -a "${REPORT_FILE}"

  (
    cd "${APP_DIR}"
    "${PYTHON_BIN}" -m ruff check src tests --select F,E9 >/dev/null
    docker compose -f docker-compose.yml --env-file .env config -q
    docker compose -f docker-compose.monolith.yml --env-file .env config -q
    ./scripts/ops.sh dev check >/dev/null
    check_security_guards
  )

  if (( i % 10 == 0 || i == ITERATIONS )); then
    (
      cd "${APP_DIR}"
      make test >/dev/null
    )
    printf '[%03d/%03d] tests ok\n' "${i}" "${ITERATIONS}" | tee -a "${REPORT_FILE}"
  fi
done

echo "All ${ITERATIONS} iterations completed successfully." | tee -a "${REPORT_FILE}"
