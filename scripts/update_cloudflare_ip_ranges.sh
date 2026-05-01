#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="${CLOUDFLARE_REALIP_OUT_FILE:-${REPO_ROOT}/ops/hetzner/nginx/snippets/shamell_cloudflare_realip.conf}"
V4_URL="${CLOUDFLARE_IPS_V4_URL:-https://www.cloudflare.com/ips-v4}"
V6_URL="${CLOUDFLARE_IPS_V6_URL:-https://www.cloudflare.com/ips-v6}"
V4_TEXT_OVERRIDE="${CLOUDFLARE_IPS_V4_TEXT:-}"
V6_TEXT_OVERRIDE="${CLOUDFLARE_IPS_V6_TEXT:-}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd curl
require_cmd date
require_cmd perl

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

fetch_cloudflare_feed() {
  local family="$1"
  local url="$2"
  local override="$3"
  if [[ -n "${override}" ]]; then
    printf '%s\n' "${override}"
    return 0
  fi
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
    --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 1 \
    "${url}"
}

validate_cloudflare_feed() {
  local family="$1"
  perl -e '
    use strict;
    use warnings;
    use Socket qw(AF_INET AF_INET6 inet_pton);

    my $family = shift @ARGV;
    my ($af, $max_prefix) = $family eq "ipv4"
      ? (AF_INET, 32)
      : (AF_INET6, 128);
    my @cidrs;

    while (my $line = <STDIN>) {
      chomp $line;
      $line =~ s/\r$//;
      $line =~ s/^\s+//;
      $line =~ s/\s+$//;
      next if $line eq q{};
      die "$family feed contains invalid CIDR line: $line\n"
        unless $line =~ m/^([^\/]+)\/(\d+)$/;
      my ($addr, $prefix) = ($1, $2);
      die "$family feed contains out-of-range prefix: $line\n"
        if $prefix > $max_prefix;
      die "$family feed contains invalid IP literal: $line\n"
        unless defined inet_pton($af, $addr);
      push @cidrs, "$addr/$prefix";
    }

    die "$family feed did not contain any CIDRs\n" unless @cidrs;
    print join("\n", @cidrs), "\n";
  ' "${family}"
}

v4="$(fetch_cloudflare_feed ipv4 "${V4_URL}" "${V4_TEXT_OVERRIDE}" | validate_cloudflare_feed ipv4)"
v6="$(fetch_cloudflare_feed ipv6 "${V6_URL}" "${V6_TEXT_OVERRIDE}" | validate_cloudflare_feed ipv6)"

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
