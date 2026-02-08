#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="${REPO_ROOT}/ops/hetzner/nginx/snippets/shamell_cloudflare_realip.conf"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd curl
require_cmd date

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

v4="$(curl -fsSL https://www.cloudflare.com/ips-v4)"
v6="$(curl -fsSL https://www.cloudflare.com/ips-v6)"

today="$(date +%Y-%m-%d)"

{
  echo "# Trust Cloudflare as a reverse proxy and restore the real client IP."
  echo "#"
  echo "# Generated from:"
  echo "# - https://www.cloudflare.com/ips-v4"
  echo "# - https://www.cloudflare.com/ips-v6"
  echo "# on ${today} (update periodically)."
  echo "#"
  echo "# Nginx will only honor CF-Connecting-IP when the TCP peer is in one of the"
  echo "# trusted Cloudflare ranges below."
  echo "real_ip_header CF-Connecting-IP;"
  echo "real_ip_recursive on;"
  echo
  echo "# Cloudflare IPv4"
  while IFS= read -r cidr; do
    [[ -z "${cidr}" ]] && continue
    echo "set_real_ip_from ${cidr};"
  done <<<"${v4}"
  echo
  echo "# Cloudflare IPv6"
  while IFS= read -r cidr; do
    [[ -z "${cidr}" ]] && continue
    echo "set_real_ip_from ${cidr};"
  done <<<"${v6}"
} >"${tmp}"

mv "${tmp}" "${OUT_FILE}"
echo "Updated ${OUT_FILE}"

