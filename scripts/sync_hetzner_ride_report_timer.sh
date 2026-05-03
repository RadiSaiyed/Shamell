#!/usr/bin/env bash
set -euo pipefail

HOST_ALIAS="${1:-shamell}"
RUN_NOW=0
REMOTE_APP_DIR="${REMOTE_APP_DIR:-}"
REMOTE_COMPOSE_FILE="${REMOTE_COMPOSE_FILE:-}"
REMOTE_ENV_FILE="${REMOTE_ENV_FILE:-}"

for arg in "${@:2}"; do
  case "$arg" in
    --run-now)
      RUN_NOW=1
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: scripts/sync_hetzner_ride_report_timer.sh [host-alias] [--run-now]" >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNITS_DIR="${REPO_ROOT}/ops/hetzner/systemd"
SERVICE_NAME="shamell-ride-ops-report.service"
TIMER_NAME="shamell-ride-ops-report.timer"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd ssh
require_cmd scp

if [[ ! -f "${UNITS_DIR}/${SERVICE_NAME}" || ! -f "${UNITS_DIR}/${TIMER_NAME}" ]]; then
  echo "Missing systemd unit files in ${UNITS_DIR}" >&2
  exit 1
fi

discover_remote_app_dir() {
  if [[ -n "${REMOTE_APP_DIR}" ]]; then
    echo "${REMOTE_APP_DIR}"
    return 0
  fi

  ssh "${HOST_ALIAS}" "bash -lc '
    user_home=\$(getent passwd \"\$(id -un)\" | cut -d: -f6)
    candidates=(/opt/shamell \"\${user_home}/shamell-src\" \"\${user_home}/shamell-pi-deploy\")
    for dir in \"\${candidates[@]}\"; do
      has_compose=0
      if [[ -f \"\$dir/ops/pi/docker-compose.postgres.yml\" || -f \"\$dir/ops/pi/docker-compose.yml\" ]]; then
        has_compose=1
      fi
      has_env=0
      if [[ -f \"\$dir/ops/pi/.env\" || -f \"\$dir/ops/pi/.env.prod\" || -f \"\$dir/ops/pi/.env.staging\" ]]; then
        has_env=1
      fi
      if [[ \"\$has_compose\" == \"1\" && \"\$has_env\" == \"1\" ]]; then
        printf \"%s\n\" \"\$dir\"
        exit 0
      fi
    done
    for dir in \"\${candidates[@]}\"; do
      if [[ -f \"\$dir/ops/pi/docker-compose.postgres.yml\" || -f \"\$dir/ops/pi/docker-compose.yml\" ]]; then
        printf \"%s\n\" \"\$dir\"
        exit 0
      fi
    done
    exit 1
  '"
}

REMOTE_APP_DIR="$(discover_remote_app_dir)" || {
  echo "Unable to detect remote app dir. Set REMOTE_APP_DIR explicitly." >&2
  exit 1
}
echo "Using remote app dir: ${REMOTE_APP_DIR}"

if [[ -z "${REMOTE_COMPOSE_FILE}" ]]; then
  if ssh "${HOST_ALIAS}" "test -f '${REMOTE_APP_DIR}/ops/pi/docker-compose.postgres.yml'"; then
    REMOTE_COMPOSE_FILE="${REMOTE_APP_DIR}/ops/pi/docker-compose.postgres.yml"
  elif ssh "${HOST_ALIAS}" "test -f '${REMOTE_APP_DIR}/ops/pi/docker-compose.yml'"; then
    REMOTE_COMPOSE_FILE="${REMOTE_APP_DIR}/ops/pi/docker-compose.yml"
  else
    echo "Unable to locate compose file under ${REMOTE_APP_DIR}/ops/pi" >&2
    exit 1
  fi
fi

if [[ -z "${REMOTE_ENV_FILE}" ]]; then
  if ssh "${HOST_ALIAS}" "test -f '${REMOTE_APP_DIR}/ops/pi/.env'"; then
    REMOTE_ENV_FILE="${REMOTE_APP_DIR}/ops/pi/.env"
  elif ssh "${HOST_ALIAS}" "test -f '${REMOTE_APP_DIR}/ops/pi/.env.prod'"; then
    REMOTE_ENV_FILE="${REMOTE_APP_DIR}/ops/pi/.env.prod"
  elif ssh "${HOST_ALIAS}" "test -f '${REMOTE_APP_DIR}/ops/pi/.env.staging'"; then
    REMOTE_ENV_FILE="${REMOTE_APP_DIR}/ops/pi/.env.staging"
  else
    REMOTE_ENV_FILE="${REMOTE_APP_DIR}/ops/pi/.env"
    echo "Warning: no env file found under ${REMOTE_APP_DIR}/ops/pi; using ${REMOTE_ENV_FILE}" >&2
  fi
fi

tmp_remote="/tmp/shamell-ride-report-systemd-sync-$$"
echo "Copying systemd units to ${HOST_ALIAS}:${tmp_remote}"
ssh "$HOST_ALIAS" "mkdir -p '$tmp_remote'"
scp \
  "${UNITS_DIR}/${SERVICE_NAME}" \
  "${UNITS_DIR}/${TIMER_NAME}" \
  "${HOST_ALIAS}:${tmp_remote}/"
scp \
  "${REPO_ROOT}/scripts/ride_ops_report.sh" \
  "${HOST_ALIAS}:${tmp_remote}/"

tmp_env_file="$(mktemp)"
cat >"${tmp_env_file}" <<EOF
APP_DIR=${REMOTE_APP_DIR}
COMPOSE_FILE=${REMOTE_COMPOSE_FILE}
ENV_FILE=${REMOTE_ENV_FILE}
EOF

for key in \
  RIDE_REPORT_MATCHING_STALE_SECS \
  RIDE_REPORT_MATCHING_NO_OFFER_STALE_SECS \
  RIDE_REPORT_PENDING_OFFER_STALE_SECS \
  RIDE_REPORT_DRIVER_PRESENCE_STALE_SECS \
  RIDE_REPORT_LIVE_STATE_STALE_SECS \
  RIDE_REPORT_RESERVED_FEE_HOLD_STALE_SECS \
  RIDE_REPORT_DETAIL_LIMIT \
  RIDE_REPORT_FAIL_ON_FINDINGS; do
  value="${!key:-}"
  if [[ -n "${value}" ]]; then
    printf '%s=%s\n' "$key" "$value" >>"${tmp_env_file}"
  fi
done

scp "${tmp_env_file}" "${HOST_ALIAS}:${tmp_remote}/shamell-ride-ops-report.env"
rm -f "${tmp_env_file}"

echo "Installing and enabling ride report timer on ${HOST_ALIAS}"
ssh -tt "$HOST_ALIAS" "
  set -euo pipefail
  install -d -m 0755 '${REMOTE_APP_DIR}/scripts'
  install -m 0755 '${tmp_remote}/ride_ops_report.sh' '${REMOTE_APP_DIR}/scripts/ride_ops_report.sh'
  sudo install -d -m 0755 /etc/systemd/system
  sudo install -m 0644 '${tmp_remote}/${SERVICE_NAME}' '/etc/systemd/system/${SERVICE_NAME}'
  sudo install -m 0644 '${tmp_remote}/${TIMER_NAME}' '/etc/systemd/system/${TIMER_NAME}'
  sudo install -d -m 0755 /etc/default
  sudo install -m 0640 '${tmp_remote}/shamell-ride-ops-report.env' '/etc/default/shamell-ride-ops-report'
  sudo systemctl daemon-reload
  sudo systemctl enable --now '${TIMER_NAME}'
  sudo systemctl restart '${TIMER_NAME}'
  sudo systemctl status --no-pager '${TIMER_NAME}' || true
  sudo systemctl list-timers --all '${TIMER_NAME}' --no-pager || true
  rm -rf '${tmp_remote}'
"

if [[ "${RUN_NOW}" == "1" ]]; then
  echo "Running ride report service immediately on ${HOST_ALIAS}"
  ssh -tt "$HOST_ALIAS" "
    set -euo pipefail
    sudo systemctl start '${SERVICE_NAME}'
    sudo systemctl status --no-pager '${SERVICE_NAME}' || true
    sudo journalctl -u '${SERVICE_NAME}' -n 60 --no-pager || true
  "
fi

echo "Ride report timer sync complete."
