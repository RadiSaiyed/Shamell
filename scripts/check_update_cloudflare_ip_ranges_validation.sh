#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/scripts/update_cloudflare_ip_ranges.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

valid_out="${tmp_dir}/valid.conf"
invalid_out="${tmp_dir}/invalid.conf"

CLOUDFLARE_REALIP_OUT_FILE="${valid_out}" \
CLOUDFLARE_IPS_V4_TEXT=$'173.245.48.0/20\n103.21.244.0/22' \
CLOUDFLARE_IPS_V6_TEXT=$'2400:cb00::/32\n2606:4700::/32' \
  bash "${SCRIPT}" >/dev/null

rg -n --fixed-strings 'real_ip_header CF-Connecting-IP;' "${valid_out}" >/dev/null
rg -n --fixed-strings 'set_real_ip_from 173.245.48.0/20;' "${valid_out}" >/dev/null
rg -n --fixed-strings 'set_real_ip_from 2400:cb00::/32;' "${valid_out}" >/dev/null

if CLOUDFLARE_REALIP_OUT_FILE="${invalid_out}" \
  CLOUDFLARE_IPS_V4_TEXT=$'not-a-cidr\n103.21.244.0/22' \
  CLOUDFLARE_IPS_V6_TEXT=$'2400:cb00::/32' \
  bash "${SCRIPT}" >/dev/null 2>"${tmp_dir}/invalid.err"; then
  echo "expected update_cloudflare_ip_ranges.sh to reject invalid feed input" >&2
  exit 1
fi

rg -n --fixed-strings 'ipv4 feed contains invalid CIDR line: not-a-cidr' "${tmp_dir}/invalid.err" >/dev/null

echo "Cloudflare IP range update validation check passed."
