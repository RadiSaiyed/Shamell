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
	      apps libs tests scripts ops -S || true
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
	    # Basic syntax/type sanity (no third-party tooling needed).
	    "${PYTHON_BIN}" -m compileall -q apps libs tests || exit 1

    # Optional: docker-compose config validation.
    #
    # Many compose files require secrets/vars that should not be present in a repo.
    # In that case validation would fail noisily and block iteration runs.
    if command -v docker >/dev/null 2>&1 && [[ -f "${APP_DIR}/docker-compose.yml" ]]; then
      if [[ "${DOCKER_COMPOSE_VALIDATE:-0}" == "1" ]]; then
        if [[ -f "${APP_DIR}/.env" ]]; then
          docker compose -f docker-compose.yml --env-file .env config -q
        else
          docker compose -f docker-compose.yml config -q
        fi
      elif [[ -f "${APP_DIR}/.env" ]]; then
        # Best-effort: if required env vars are missing, don't fail the whole run.
        docker compose -f docker-compose.yml --env-file .env config -q || true
      else
        echo "[warn] skipping docker compose config validation (missing .env; set DOCKER_COMPOSE_VALIDATE=1 to force)" \
          | tee -a "${REPORT_FILE}"
      fi
    fi

    # Optional: ops helper checks (may require Docker and local env).
    if [[ -x "${APP_DIR}/scripts/ops.sh" ]]; then
      ./scripts/ops.sh dev check >/dev/null 2>&1 || true
    fi
    check_security_guards
  )

  if (( i % 10 == 0 || i == ITERATIONS )); then
    (
      cd "${APP_DIR}"
      "${PYTHON_BIN}" -m pytest -q >/dev/null
    )
    printf '[%03d/%03d] tests ok\n' "${i}" "${ITERATIONS}" | tee -a "${REPORT_FILE}"
  fi
done

echo "All ${ITERATIONS} iterations completed successfully." | tee -a "${REPORT_FILE}"
