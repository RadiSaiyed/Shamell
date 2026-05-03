#!/usr/bin/env bash
set -euo pipefail

max_attempts="${CARGO_AUDIT_MAX_ATTEMPTS:-3}"
net_retry="${CARGO_AUDIT_NET_RETRY:-8}"
http_timeout="${CARGO_AUDIT_HTTP_TIMEOUT:-180}"
backoff_secs="${CARGO_AUDIT_BACKOFF_SECS:-3}"

attempt=1
while true; do
  echo "cargo audit attempt ${attempt}/${max_attempts}"
  if CARGO_NET_RETRY="${net_retry}" CARGO_HTTP_TIMEOUT="${http_timeout}" cargo audit -D warnings; then
    echo "cargo audit passed"
    exit 0
  fi
  if (( attempt >= max_attempts )); then
    echo "cargo audit failed after ${max_attempts} attempts" >&2
    exit 1
  fi
  sleep "$((backoff_secs * attempt))"
  attempt=$((attempt + 1))
done
