#!/usr/bin/env bash
set -euo pipefail

API_HOST="${API_HOST:-api.shamell.online}"
UPSTREAM_BASE="${UPSTREAM_BASE:-http://127.0.0.1:8080}"
EDGE_BASE="${EDGE_BASE:-https://127.0.0.1}"
MAX_RESPONSE_MS="${MAX_RESPONSE_MS:-2500}"

expect_code() {
  local label="$1"
  local method="$2"
  local url="$3"
  local expected="$4"
  local host_header="${5:-}"

  local tmp
  tmp="$(mktemp)"
  local -a args
  args=(-sS -o "$tmp" -w "%{http_code} %{time_total}" -X "$method" "$url")
  if [[ "$url" == https:* ]]; then
    args+=(-k)
  fi
  if [[ -n "$host_header" ]]; then
    args+=(-H "Host: $host_header")
  fi

  local out code time_s latency_ms
  out="$(curl "${args[@]}")"
  code="${out%% *}"
  time_s="${out##* }"
  latency_ms="$(awk -v t="$time_s" 'BEGIN {printf "%.0f", t * 1000}')"

  if [[ "$code" != "$expected" || "$latency_ms" -gt "$MAX_RESPONSE_MS" ]]; then
    echo "[FAIL] ${label}: code=${code} expected=${expected} latency_ms=${latency_ms} max_ms=${MAX_RESPONSE_MS}" >&2
    sed -n '1,120p' "$tmp" >&2 || true
    rm -f "$tmp"
    exit 1
  fi

  echo "[PASS] ${label}: code=${code} latency_ms=${latency_ms}"
  rm -f "$tmp"
}

expect_code "Monolith upstream health" GET "${UPSTREAM_BASE}/health" "200"
# In prod we keep raw service routers disabled; validate that the BFF admin surface
# is not reachable without auth (regardless of whether service routers are exposed).
expect_code "BFF payments admin guard (upstream)" GET "${UPSTREAM_BASE}/payments/admin/risk/metrics" "401"
expect_code "Edge health via nginx host route" GET "${EDGE_BASE}/health" "200" "$API_HOST"
expect_code "BFF payments admin guard (edge)" GET "${EDGE_BASE}/payments/admin/risk/metrics" "401" "$API_HOST"

echo "deploy_pi smoke guard checks passed."
