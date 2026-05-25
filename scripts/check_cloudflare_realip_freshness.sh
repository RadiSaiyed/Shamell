#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNIPPET_PATH="${CLOUDFLARE_REALIP_SNIPPET:-${ROOT}/ops/hetzner/nginx/snippets/shamell_cloudflare_realip.conf}"
MAX_AGE_DAYS="${CLOUDFLARE_REALIP_MAX_AGE_DAYS:-30}"

if [[ ! "$MAX_AGE_DAYS" =~ ^[0-9]+$ ]]; then
  echo "CLOUDFLARE_REALIP_MAX_AGE_DAYS must be a non-negative integer." >&2
  exit 1
fi

if [[ ! -f "$SNIPPET_PATH" ]]; then
  echo "Missing Cloudflare real-ip snippet: $SNIPPET_PATH" >&2
  exit 1
fi

stamp_line="$(grep -E '^# on [0-9]{4}-[0-9]{2}-[0-9]{2} \(update periodically\)\.$' "$SNIPPET_PATH" | head -n1 || true)"
if [[ -z "$stamp_line" ]]; then
  echo "Cloudflare real-ip snippet is missing a generated-on date comment: $SNIPPET_PATH" >&2
  exit 1
fi

stamp_date="$(printf '%s\n' "$stamp_line" | sed -E 's/^# on ([0-9]{4}-[0-9]{2}-[0-9]{2}) \(update periodically\)\.$/\1/')"

age_days="$(
  perl -MTime::Piece -e '
    my ($stamp, $max) = @ARGV;
    my $t = Time::Piece->strptime($stamp, "%Y-%m-%d");
    my $now = localtime;
    my $age = int(($now->epoch - $t->epoch) / 86400);
    print $age;
  ' "$stamp_date" "$MAX_AGE_DAYS"
)"

if [[ ! "$age_days" =~ ^-?[0-9]+$ ]]; then
  echo "Failed to compute Cloudflare real-ip snippet age for $SNIPPET_PATH" >&2
  exit 1
fi

if (( age_days < 0 )); then
  echo "Cloudflare real-ip snippet date is in the future (${stamp_date}): $SNIPPET_PATH" >&2
  exit 1
fi

if (( age_days > MAX_AGE_DAYS )); then
  echo "Cloudflare real-ip snippet is stale (${age_days}d > ${MAX_AGE_DAYS}d): $SNIPPET_PATH" >&2
  echo "Refresh it with: bash scripts/update_cloudflare_ip_ranges.sh" >&2
  exit 1
fi

echo "Cloudflare real-ip snippet freshness check passed (${age_days}d <= ${MAX_AGE_DAYS}d)."
